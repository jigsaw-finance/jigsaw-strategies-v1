// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma abicoder v2;

import "../fixtures/BasicContractsFixture.t.sol";

import "forge-std/Test.sol";

import "forge-std/console.sol";
import {ElixirStrategy} from "../../src/elixir/ElixirStrategy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {StakerLight} from "../../src/staker/StakerLight.sol";
import {StakerLightFactory} from "../../src/staker/StakerLightFactory.sol";

contract ElixirStrategyTest is Test, BasicContractsFixture {
    using SafeERC20 for IERC20;
    // Mainnet USDT
    address internal tokenIn = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    // sdeUSD token
    address internal tokenOut = 0x5C5b196aBE0d54485975D1Ec29617D42D9198326;
    // deUSD token
    address internal deUSD = 0x15700B564Ca08D9439C58cA5053166E8317aa138;
    uint24 public constant poolFee = 100;

    ElixirStrategy internal strategy;

    function setUp() public {
        init();

        address strategyImplementation = address(new ElixirStrategy());
        ElixirStrategy.InitializerParams memory initParams = ElixirStrategy.InitializerParams({
            owner: OWNER,
            managerContainer: address(managerContainer),
            stakerFactory: address(stakerFactory),
            jigsawRewardToken: jRewards,
            jigsawRewardDuration: 60 days,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            deUSD: deUSD
        });

        bytes memory data = abi.encodeCall(ElixirStrategy.initialize, initParams);
        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = ElixirStrategy(proxy);

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
    function test_elixir_deposit_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        // added to prevent USDT safeTransferFrom revert issue
        assumeNotPrecompile(user);
        uint256 amount = bound(_amount, 1e6, 10e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        uint256 tokenOutBalanceBefore = IERC20(tokenOut).balanceOf(userHolding);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) = strategyManager.invest(
            tokenIn,
            address(strategy),
            amount,
            abi.encodePacked(tokenIn, poolFee, deUSD)
        );

        uint256 tokenOutBalanceAfter = IERC20(tokenOut).balanceOf(userHolding);
        uint256 expectedShares = tokenOutBalanceAfter - tokenOutBalanceBefore;
        (uint256 investedAmount, uint256 totalShares) = strategy.recipients(userHolding);

        /**
         * Expected changes after deposit
         * 1. Holding tokenIn balance =  balance - amount
         * 2. Holding tokenOut balance += amount
         * 3. Staker receiptTokens balance += shares
         * 4. Strategy's invested amount  += amount
         * 5. Strategy's total shares  += shares
         */
        assertEq(IERC20(tokenIn).balanceOf(userHolding), tokenInBalanceBefore - amount, "Holding tokenIn balance wrong");
        // allow 10% difference for tokenOut balance
        assertApproxEqRel(
            IERC20(tokenOut).balanceOf(userHolding),
            amount * 1e12,
            0.1e18,
            "Holding token out balance wrong");
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            expectedShares,
            "Incorrect receipt tokens minted"
        );
        assertEq(investedAmount, amount, "Recipient invested amount mismatch");
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");

        // Additional checks
        assertApproxEqRel(
            tokenOutBalanceAfter,
            amount * 1e12,
            0.04e18,
            "Wrong balance in Elixir after stake"
        );
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
    }

//    // Tests if withdraw works correctly when authorized
//    function test_elixir_withdraw_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
//        uint256 amount = bound(_amount, 1e18, 10e18);
//        address userHolding = initiateUser(user, tokenIn, amount, false);
//
//        // Invest into the tested strategy vie strategyManager
//        vm.prank(user, user);
//        strategyManager.invest(tokenIn, address(strategy), amount, "");
//
//        (uint256 investedAmountBefore, uint256 totalShares) = strategy.recipients(userHolding);
//        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
//
//        skip(100 days);
//
//        // Increase the balance of the autoPxEth with pxETH
//        uint256 addedRewards = 1e22;
//        deal(address(PX_ETH), address(AUTO_PIREX_ETH), addedRewards);
//        // Updated rewards state variable in autoPxEth contract
//        vm.store(address(AUTO_PIREX_ETH), bytes32(uint256(14)), bytes32(uint256(addedRewards)));
//
//        // Pirex ETH takes fee for instant redemption
//        uint256 postRedemptionFeeAssetAmt = subtractPercent(
//            AUTO_PIREX_ETH.previewRedeem(totalShares), PIREX_ETH.fees(IPirexEth.Fees.InstantRedemption) / 1000
//        );
//
//        // Compute Jigsaw's performance fee
//        uint256 fee = investedAmountBefore >= postRedemptionFeeAssetAmt
//            ? 0
//            : _getFeeAbsolute(postRedemptionFeeAssetAmt - investedAmountBefore, manager.performanceFee());
//
//        vm.prank(user, user);
//        (uint256 assetAmount,) = strategyManager.claimInvestment({
//            _holding: userHolding,
//            _strategy: address(strategy),
//            _shares: totalShares,
//            _asset: tokenIn,
//            _data: ""
//        });
//
//        (uint256 investedAmount, uint256 totalSharesAfter) = strategy.recipients(userHolding);
//        uint256 tokenInBalanceAfter = IERC20(tokenIn).balanceOf(userHolding);
//        uint256 expectedWithdrawal = tokenInBalanceAfter - tokenInBalanceBefore;
//
//        /**
//         * Expected changes after withdrawal
//         * 1. Holding's tokenIn balance += (totalInvested + yield) * shareRatio
//         * 2. Holding's tokenOut balance -= shares
//         * 3. Staker receiptTokens balance -= shares
//         * 4. Strategy's invested amount  -= totalInvested * shareRatio
//         * 5. Strategy's total shares  -= shares
//         * 6. Fee address fee amount += yield * performanceFee
//         */
//        assertEq(tokenInBalanceAfter, assetAmount, "Holding balance after withdraw is wrong");
//        assertEq(IERC20(tokenOut).balanceOf(userHolding), 0, "Holding token out balance wrong");
//        assertEq(
//            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
//            0,
//            "Incorrect receipt tokens after withdraw"
//        );
//        assertEq(investedAmount, 0, "Recipient invested amount mismatch");
//        assertEq(totalSharesAfter, 0, "Recipient total shares mismatch after withdrawal");
//        assertEq(fee, IERC20(tokenIn).balanceOf(manager.feeAddress()), "Fee address fee amount wrong");
//
//        // Additional checks
//        assertEq(tokenInBalanceAfter, expectedWithdrawal, "Incorrect asset amount returned");
//    }
//
//    // percent == 0.1%
//    function subtractPercent(uint256 value, uint256 percent) public pure returns (uint256) {
//        uint256 deduction = (value * percent) / 1000; // 0.5% is 5/1000
//        return value - deduction;
//    }
}