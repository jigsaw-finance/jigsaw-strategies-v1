// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IPirexEth } from "../../src/dinero/IPirexEth.sol";
import { IAutoPxEth } from "../../src/dinero/IAutoPxEth.sol";
import { DineroStrategy } from "../../src/dinero/DineroStrategy.sol";
import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";

IPirexEth constant PIREX_ETH = IPirexEth(0xD664b74274DfEB538d9baC494F3a4760828B02b0);
IAutoPxEth constant AUTO_PIREX_ETH = IAutoPxEth(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6);

contract DineroAutoPxStrategyTest is Test, BasicContractsFixture {
    // Mainnet wETH
    address internal tokenIn = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // apxETH token
    address internal tokenOut = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;

    DineroStrategy internal strategy;

    function setUp() public {
        init();

        address jRewards = address(new ERC20Mock());
        address stakerFactory = address(new StakerLightFactory({ _initialOwner: OWNER }));
        address strategyImplementation = address(new DineroStrategy());

        DineroStrategy.InitializerParams memory initParams = DineroStrategy.InitializerParams({
            owner: OWNER,
            managerContainer: address(managerContainer),
            stakerFactory: address(stakerFactory),
            pirexEth: address(PIREX_ETH),
            autoPirexEth: address(AUTO_PIREX_ETH),
            jigsawRewardToken: jRewards,
            jigsawRewardDuration: 60 days,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            shouldStake: true
        });

        bytes memory data = abi.encodeCall(DineroStrategy.initialize, initParams);
        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = DineroStrategy(payable(proxy));

        // Add tested strategy to the StrategyManager for integration testing purposes
        vm.startPrank((OWNER));
        manager.whitelistToken(tokenIn);
        strategyManager.addStrategy(address(strategy));

        SharesRegistry tokenInSharesRegistry = new SharesRegistry(
            OWNER, address(managerContainer), address(tokenIn), address(usdcOracle), bytes(""), 50_000
        );
        stablesManager.registerOrUpdateShareRegistry(address(tokenInSharesRegistry), address(tokenIn), true);
        registries[address(tokenIn)] = address(tokenInSharesRegistry);
        vm.stopPrank();
    }

    // Tests if deposit works correctly when authorized
    function test_dinero_px_eth_deposit_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 10e18);

        address userHolding = initiateUser(user, tokenIn, amount, false);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(userHolding);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) = strategyManager.invest(tokenIn, address(strategy), amount, "");

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(userHolding);
        uint256 expectedShares = balanceAfter - balanceBefore;
        (uint256 investedAmount, uint256 totalShares) = strategy.recipients(userHolding);

        uint256 sharesReturned = (strategy.autoPirexEth().convertToShares(amount));
        assertApproxEqRel(balanceAfter, sharesReturned, 0.01e18, "Wrong balance in Dinero after stake");
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
        assertEq(investedAmount, expectedShares, "Recipient invested amount mismatch");
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");
        assertEq(strategy.totalInvestments(), expectedShares, "Total investments mismatch");
    }

    // Tests if withdraw works correctly when authorized
    function test_dinero_px_eth_withdraw_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 10e18);

        // Mock values and setup necessary approvals and balances for the test
        address userHolding = initiateUser(user, tokenIn, amount, false);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, "");

        (, uint256 totalShares) = strategy.recipients(userHolding);

        vm.prank(user, user);
        strategyManager.claimInvestment({
            _holding: userHolding,
            _strategy: address(strategy),
            _shares: totalShares,
            _asset: tokenIn,
            _data: ""
        });

        uint256 balanceAfter = IERC20(tokenIn).balanceOf(userHolding);

        uint256 expectedWithdrawal = subtractPercent(totalShares, 5);

        (, uint256 totalSharesAfter) = strategy.recipients(userHolding);

        // Assert statements with reasons
        assertEq(balanceAfter, expectedWithdrawal, "Incorrect asset amount returned");
        assertEq(totalSharesAfter, 0, "Recipient total shares mismatch after withdrawal");
        assertEq(strategy.totalInvestments(), 0, "Total investments mismatch after withdrawal");
    }

    // percent == 0.1%
    function subtractPercent(uint256 value, uint256 percent) public pure returns (uint256) {
        uint256 deduction = (value * percent) / 1000; // 0.5% is 5/1000
        return value - deduction;
    }
}