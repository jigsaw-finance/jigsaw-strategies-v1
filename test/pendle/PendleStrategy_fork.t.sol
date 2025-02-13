// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

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
address constant PENDLE_MARKET = 0x58612beB0e8a126735b19BB222cbC7fC2C162D2a; // pufETH pendle market address

contract PendleStrategyTest is Test, BasicContractsFixture {
    // Mainnet pufETH
    address internal tokenIn = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    // Pendle LP token
    address internal tokenOut = PENDLE_MARKET;
    // Pendle reward token
    address internal rewardToken = 0x808507121B80c02388fAd14726482e061B8da827;

    PendleStrategy internal strategy;

    // EmptySwap means no swap aggregator is involved
    SwapData internal emptySwap;

    // EmptyLimit means no limit order is involved
    LimitOrderData internal emptyLimit;

    // DefaultApprox means no off-chain preparation is involved, more gas consuming (~ 180k gas)
    ApproxParams public defaultApprox =
        ApproxParams({ guessMin: 0, guessMax: type(uint256).max, guessOffchain: 0, maxIteration: 256, eps: 1e14 });

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
        uint256 amount = bound(_amount, 1e18, 10e18);
        address userHolding = initiateUser(user, tokenIn, amount);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        uint256 tokenOutBalanceBefore = IERC20(tokenOut).balanceOf(userHolding);

        // Invest into the tested strategy via strategyManager
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

        uint256 tokenOutbalanceAfter = IERC20(tokenOut).balanceOf(userHolding);
        uint256 expectedShares = tokenOutbalanceAfter - tokenOutBalanceBefore;
        (uint256 investedAmount, uint256 totalShares) = strategy.recipients(userHolding);

        /**
         * Expected changes after deposit
         * 1. Holding tokenIn balance =  balance - amount
         * 2. Holding tokenOut balance += amount
         * 3. Staker receiptTokens balance += shares
         * 4. Strategy's invested amount  += amount
         * 5. Strategy's total shares  += shares
         */
        // 1.
        assertEq(IERC20(tokenIn).balanceOf(userHolding), tokenInBalanceBefore - amount, "Holding tokenIn balance wrong");
        // 2.
        assertApproxEqRel(
            IERC20(tokenOut).balanceOf(userHolding), amount / 2, 0.05e18, "Holding token out balance wrong"
        );
        // 3.
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            expectedShares,
            "Incorrect receipt tokens minted"
        );
        //4.
        assertEq(investedAmount, amount, "Recipient invested amount mismatch");
        //5.
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");

        // Additional checks
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
        assertEq(tokenOutbalanceAfter, tokenOutBalanceBefore + totalShares, "Wrong LP balance in Pendle after mint");
    }

    // Tests if withdrawal works correctly when authorized
    function test_pendle_withdraw_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 10e18);
        address userHolding = initiateUser(user, tokenIn, amount);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 investedAmountBefore, uint256 tokenInAmount) = strategyManager.invest(
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
        uint256 expectedTokenInBalanceMin = amount * withdrawalShares / totalShares;

        skip(100 days);

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

        (, uint256 updatedShares) = strategy.recipients(userHolding);

        assertGe(IERC20(tokenIn).balanceOf(userHolding), expectedTokenInBalanceMin, "Withdraw amount wrong");
        assertEq(updatedShares, totalShares - withdrawalShares, "Shares amount updated wrong");

        (uint256 investedAmountAfterFirstWithdraw,) = strategy.recipients(userHolding);

        if (totalShares - withdrawalShares == 0) {
            assertEq(IERC20(tokenOut).balanceOf(userHolding), 0, "Wrong token out amount after first withdraw");
            assertEq(
                IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
                0,
                "Incorrect receipt tokens after first withdraw"
            );
            assertEq(investedAmountAfterFirstWithdraw, 0, "Recipient invested amount mismatch after first withdraw");
            assertGt(
                IERC20(tokenIn).balanceOf(manager.feeAddress()), 0, "Fee address fee amount wrong after first withdraw"
            );

            return;
        }

        // withdraw the rest
        vm.prank(user, user);
        strategyManager.claimInvestment(userHolding, address(strategy), totalShares - withdrawalShares, tokenIn, "");
        (uint256 investedAmount, uint256 totalSharesAfter) = strategy.recipients(userHolding);

        uint256 fee =
            _getFeeAbsolute(IERC20(tokenOut).balanceOf(userHolding) - investedAmountBefore, manager.performanceFee());

        /**
         * Expected changes after withdrawal
         * 1. Holding's tokenIn balance += (totalInvested + yield) * shareRatio
         * 2. Holding's tokenOut balance -= shares
         * 3. Staker receiptTokens balance -= shares
         * 4. Strategy's invested amount  -= totalInvested * shareRatio
         * 5. Strategy's total shares  -= shares
         * 6. Fee address fee amount += yield * performanceFee
         */
        //1.
        assertEq(IERC20(tokenIn).balanceOf(userHolding), tokenInBalanceBefore - amount, "Withdraw amount wrong");
        // 2.
        assertEq(IERC20(tokenOut).balanceOf(userHolding), 0, "Wrong token out  amount");
        // 3.
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            0,
            "Incorrect receipt tokens after withdraw"
        );
        // 4.
        assertEq(investedAmount, 0, "Recipient invested amount mismatch");
        // 5.
        assertEq(totalSharesAfter, 0, "Recipient total shares mismatch after withdrawal");
        // 6.
        assertEq(fee, IERC20(tokenIn).balanceOf(manager.feeAddress()), "Fee address fee amount wrong");

        // Additional checks
        assertEq(tokenInAmount, investedAmountBefore, "Incorrect tokenInAmount returned");
    }

    function test_pendle_claimRewards_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 10e18);
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
