// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@pendle/interfaces/IPAllActionV3.sol";
import { IPMarket, IPYieldToken, IStandardizedYield } from "@pendle/interfaces/IPMarket.sol";
import { IPSwapAggregator } from "@pendle/router/swap-aggregator/IPSwapAggregator.sol";

import { PendleStrategy } from "../../src/pendle/PendleStrategy.sol";

address constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;
address constant PENDLE_MARKET = 0x676106576004EF54B4bD39Ce8d2B34069F86eb8f; // pufETH pendle market address

contract PendleStrategyTest is Test, BasicContractsFixture {
    // Mainnet pufETH
    address internal tokenIn = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    // Pendle LP token
    address internal tokenOut = 0x676106576004EF54B4bD39Ce8d2B34069F86eb8f;
    // Pendle reward token
    address internal rewardToken = 0x808507121B80c02388fAd14726482e061B8da827;

    PendleStrategy internal strategy;

    // EmptySwap means no swap aggregator is involved
    SwapData internal emptySwap;

    // EmptyLimit means no limit order is involved
    LimitOrderData internal emptyLimit;

    // DefaultApprox means no off-chain preparation is involved, more gas consuming (~ 180k gas)
    ApproxParams public defaultApprox = ApproxParams(0, type(uint256).max, 0, 256, 1e14);

    function setUp() public {
        init();

        address strategyImplementation = address(new PendleStrategy());
        bytes memory data = abi.encodeCall(
            PendleStrategy.initialize,
            PendleStrategy.InitializerParams({
                owner: OWNER,
                managerContainer: address(managerContainer),
                pendleRouter: PENDLE_ROUTER,
                pendleMarket: PENDLE_MARKET,
                stakerFactory: address(stakerFactory),
                jigsawRewardToken: jRewards,
                jigsawRewardDuration: 60 days,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                rewardToken: rewardToken
            })
        );

        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = PendleStrategy(proxy);

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
    function test_pendle_deposit_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 100_000e18);
        address userHolding = initiateUser(user, tokenIn, amount);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(userHolding);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) = strategyManager.invest(
            tokenIn,
            address(strategy),
            amount,
            abi.encode(
                0,
                defaultApprox,
                TokenInput({
                    tokenIn: tokenIn,
                    netTokenIn: amount,
                    tokenMintSy: tokenIn,
                    pendleSwap: address(0),
                    swapData: emptySwap
                }),
                emptyLimit
            )
        );

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(userHolding);
        uint256 expectedShares = balanceAfter - balanceBefore;

        (uint256 investedAmount, uint256 totalShares) = strategy.recipients(userHolding);

        assertEq(balanceAfter, balanceBefore + totalShares, "Wrong LP balance in Pendle after mint");
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
        assertEq(investedAmount, amount, "Recipient invested amount mismatch");
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");
    }

    // Tests if withdrawal works correctly when authorized
    function test_pendle_claimInvestment_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 100_000e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(
            tokenIn,
            address(strategy),
            amount,
            abi.encode(
                0,
                defaultApprox,
                TokenInput({
                    tokenIn: tokenIn,
                    netTokenIn: amount,
                    tokenMintSy: tokenIn,
                    pendleSwap: address(0),
                    swapData: emptySwap
                }),
                emptyLimit
            )
        );

        (, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 withdrawalShares = bound(totalShares, 1, totalShares);
        uint256 underlyingBefore = IERC20(tokenIn).balanceOf(userHolding);
        uint256 expectedUnderlyingAfter = amount * withdrawalShares / totalShares;

        vm.prank(user, user);
        strategyManager.claimInvestment(
            userHolding,
            address(strategy),
            withdrawalShares,
            tokenIn,
            abi.encode(
                TokenOutput({
                    tokenOut: tokenIn,
                    minTokenOut: 0,
                    tokenRedeemSy: tokenIn,
                    pendleSwap: address(0),
                    swapData: emptySwap
                }),
                emptyLimit
            )
        );

        uint256 underlyingAfter = IERC20(tokenIn).balanceOf(userHolding);
        (, uint256 updatedShares) = strategy.recipients(userHolding);

        assertApproxEqRel(
            underlyingAfter - underlyingBefore, expectedUnderlyingAfter, 0.001e18, "Withdraw amount wrong"
        ); // 0.1% approximation is allowed
        assertEq(totalShares - withdrawalShares, updatedShares, "Shares amount updated wrong");

        if (totalShares - withdrawalShares == 0) return;

        // withdraw the rest
        vm.prank(user, user);
        strategyManager.claimInvestment(userHolding, address(strategy), totalShares - withdrawalShares, tokenIn, "");
        (, uint256 finalShares) = strategy.recipients(userHolding);

        assertApproxEqRel(IERC20(tokenIn).balanceOf(userHolding), amount, 0.001e18, "Withdrawn wrong amount"); // 0.1%
            // approximation is allowed
        assertEq(IERC20(tokenOut).balanceOf(userHolding), 0, "Wrong token out  amount");
        assertEq(finalShares, 0, "Shares amount updated wrong");
    }

    function test_pendle_claimRewards_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 100_000e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(
            tokenIn,
            address(strategy),
            amount,
            abi.encode(
                0,
                defaultApprox,
                TokenInput({
                    tokenIn: tokenIn,
                    netTokenIn: amount,
                    tokenMintSy: tokenIn,
                    pendleSwap: address(0),
                    swapData: emptySwap
                }),
                emptyLimit
            )
        );
        vm.roll(vm.getBlockNumber() + 100);
        skip(100 days);

        vm.prank(user, user);
        (uint256[] memory rewards, address[] memory tokens) = strategyManager.claimRewards(address(strategy), "");

        uint256 userRewards = IERC20(strategy.rewardToken()).balanceOf(userHolding);
        uint256 feeAddrRewards = IERC20(strategy.rewardToken()).balanceOf(manager.feeAddress());

        uint256 performanceFee = 1500;
        uint256 precision = 10_000;
        uint256 expectedFees = rewards[0] / (1 - performanceFee / precision) * performanceFee / precision;

        assertEq(rewards[0], userRewards, "User rewards amount wrong");
        assertEq(tokens[0], rewardToken, "Reward token is wrong");
        assertGt(feeAddrRewards, expectedFees, "Fee amount wrong");
    }
}
