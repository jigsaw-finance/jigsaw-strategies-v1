// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "../fixtures/BasicContractsFixture.t.sol";
import "forge-std/Test.sol";

import { FeeManager } from "../../src/extensions/FeeManager.sol";
import { StrategyMockImpl } from "./StrategyMockImpl.sol";
import { StrategyV2MockImpl } from "./StrategyV2MockImpl.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StrategyBaseV2Test is BasicContractsFixture {
    // Example tokenIn
    address internal tokenIn = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Example tokenOut
    address internal tokenOut = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;

    error OwnableUnauthorizedAccount(address account);

    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);

    StrategyMockImpl internal strategy;
    StrategyV2MockImpl internal strategyV2;

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

        // Deploy the new implementation
        address strategyV2Implementation = address(new StrategyV2MockImpl());

        // Perform the upgrade
        bytes memory updateData = abi.encodeCall(
            StrategyV2MockImpl.initialize, StrategyV2MockImpl.InitializerParams({ feeManager: address(feeManager) })
        );

        strategy.upgradeToAndCall(strategyV2Implementation, updateData);
        strategyV2 = StrategyV2MockImpl(address(strategy));
        vm.stopPrank();
    }

    function test_setFeeManagerAndExpectEmit() public {
        FeeManager newFeeManager = new FeeManager(OWNER, address(manager));

        vm.prank(OWNER);

        vm.expectEmit(true, true, false, false);
        emit FeeManagerUpdated(address(feeManager), address(newFeeManager));

        strategyV2.setFeeManager(address(newFeeManager));
        assertEq(
            address(strategyV2.feeManager()),
            address(newFeeManager),
            "New FeeManager address should be set successfully"
        );
    }

    function test_revertsWhenRenouncingOwnership() public {
        address user = address(0x456);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        strategyV2.setFeeManager(user);
    }

    function test_retrievesFeeManagerSuccessfully() public view {
        assertEq(
            address(strategyV2.feeManager()),
            address(feeManager),
            "Fee manager address should be retrieved successfully"
        );
    }

    function test_revertsWhenFeeManagerIsNotSet() public {
        vm.startPrank(OWNER);
        vm.expectRevert(bytes("3000"));
        strategyV2.setFeeManager(address(0));
    }

    function test_revertsWhenSameFeeManagerIsSet() public {
        vm.startPrank(OWNER);
        vm.expectRevert(bytes("3017"));
        strategyV2.setFeeManager(address(feeManager));
    }
}
