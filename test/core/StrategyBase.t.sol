// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "../fixtures/BasicContractsFixture.t.sol";
import "forge-std/Test.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { FeeManager } from "../../src/extensions/FeeManager.sol";
import { StrategyMockImpl } from "./StrategyMockImpl.sol";

contract StrategyBaseTest is BasicContractsFixture {
    // Example tokenIn
    address internal tokenIn = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Example tokenOut
    address internal tokenOut = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;

    error OwnableUnauthorizedAccount(address account);

    StrategyMockImpl internal strategy;

    function setUp() public {
        init();

        address strategyImplementation = address(new StrategyMockImpl());
        StrategyMockImpl.InitializerParams memory initParams = StrategyMockImpl.InitializerParams({
            owner: OWNER,
            manager: address(manager),
            jigsawRewardToken: jRewards,
            jigsawRewardDuration: 60 days,
            tokenIn: tokenIn,
            tokenOut: tokenOut
        });

        bytes memory data = abi.encodeCall(StrategyMockImpl.initialize, initParams);
        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = StrategyMockImpl(payable(proxy));

        // Add tested strategy to the StrategyManager for integration testing purposes
        vm.startPrank(OWNER);
        strategyManager.addStrategy(address(strategy));

        SharesRegistry tokenInSharesRegistry = new SharesRegistry(
            OWNER,
            address(manager),
            address(tokenIn),
            address(usdcOracle),
            bytes(""),
            ISharesRegistry.RegistryConfig({
                collateralizationRate: 50_000,
                liquidationBuffer: 5e3,
                liquidatorBonus: 8e3
            })
        );
        stablesManager.registerOrUpdateShareRegistry(address(tokenInSharesRegistry), address(tokenIn), true);
        registries[address(tokenIn)] = address(tokenInSharesRegistry);
        vm.stopPrank();
    }

    function test_savesFundsSuccessfully() public {
        uint256 amount = 500 * 10e18;
        deal(tokenIn, address(strategy), amount);

        vm.prank(OWNER);
        strategy.emergencySave(tokenIn, amount);

        assertEq(IERC20(tokenIn).balanceOf(OWNER), amount, "Funds should be saved successfully");
    }

    function test_revertsWhenSavingFundsExceedingBalance() public {
        uint256 amount = 500 * 10e18;

        vm.prank(OWNER);
        vm.expectRevert(bytes("2005"));
        strategy.emergencySave(tokenIn, amount);
    }

    function test_revertsWhenSavingFundsToZeroAddress() public {
        uint256 amount = 500 * 10e18;

        vm.prank(OWNER);
        vm.expectRevert(bytes("3000"));
        strategy.emergencySave(address(0), amount);
    }

    function test_revertsWhenNonOwnerSavesFunds() public {
        uint256 amount = 500 * 10e18;

        deal(tokenIn, address(this), amount);

        vm.prank(address(0x456));
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0x456)));
        strategy.emergencySave(tokenIn, amount);
    }

    function test_revertsWhenRenouncingOwnership() public {
        vm.expectRevert(bytes("1000"));
        strategy.renounceOwnership();
    }
}
