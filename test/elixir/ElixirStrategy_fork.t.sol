// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma abicoder v2;

import "../fixtures/BasicContractsFixture.t.sol";

import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ElixirStrategy} from "../../src/elixir/ElixirStrategy.sol";
import {IstdeUSD} from "../../src/elixir/interfaces/IstdeUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {StakerLight} from "../../src/staker/StakerLight.sol";
import {StakerLightFactory} from "../../src/staker/StakerLightFactory.sol";

contract ElixirStrategyTest is Test, BasicContractsFixture {
    using SafeERC20 for IERC20;
    // Mainnet USDT
    address internal tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // sdeUSD token
    address internal tokenOut = 0x5C5b196aBE0d54485975D1Ec29617D42D9198326;
    // deUSD token
    address internal deUSD = 0x15700B564Ca08D9439C58cA5053166E8317aa138;

    address internal uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address internal user = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

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
            deUSD: deUSD,
            uniswapRouter: uniswapRouter
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
    function test_elixir_deposit_when_authorized(uint256 _amount) public notOwnerNotZero(user) {
        // added to prevent USDT safeTransferFrom revert issue
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
        // allow 5% difference for tokenOut balance
        assertApproxEqRel(
            IERC20(tokenOut).balanceOf(userHolding),
            amount * 1e12,
            0.05e18,
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
            amount * 1e12, // TODO: decimals are different
            1e18, // TODO: ensure delta is correct
            "Wrong balance in Elixir after stake"
        );
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
    }

    // Tests if withdraw works correctly when authorized
    function test_elixir_withdraw_when_authorized(uint256 _amount) public notOwnerNotZero(user) {
        // added to prevent USDT safeTransferFrom revert issue
        uint256 amount = bound(_amount, 1e6, 100000e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) = strategyManager.invest(
            tokenIn,
            address(strategy),
            amount,
            abi.encodePacked(tokenIn, poolFee, deUSD)
        );

        (uint256 investedAmountBefore, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);

        _transferInRewards(100000e18);
        skip(90 days);

        strategy.cooldown(userHolding, totalShares);
        skip(7 days);

        vm.prank(user, user);
        (uint256 assetAmount,) = strategyManager.claimInvestment({
            _holding: userHolding,
            _strategy: address(strategy),
            _shares: totalShares,
            _asset: tokenIn,
            _data: abi.encodePacked(deUSD, poolFee, tokenIn)
        });

        (uint256 investedAmount, uint256 totalSharesAfter) = strategy.recipients(userHolding);
        uint256 tokenInBalanceAfter = IERC20(tokenIn).balanceOf(userHolding);
        uint256 expectedWithdrawal = tokenInBalanceAfter - tokenInBalanceBefore;

        /**
         * Expected changes after withdrawal
         * 1. Holding's tokenIn balance += (totalInvested + yield) * shareRatio
         * 2. Holding's tokenOut balance -= shares
         * 3. Staker receiptTokens balance -= shares
         * 4. Strategy's invested amount  -= totalInvested * shareRatio
         * 5. Strategy's total shares  -= shares
         * 6. Fee address fee amount += yield * performanceFee
         */
        assertEq(tokenInBalanceAfter, assetAmount, "Holding balance after withdraw is wrong");
        assertEq(IERC20(tokenOut).balanceOf(userHolding), 0, "Holding token out balance wrong");
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            0,
            "Incorrect receipt tokens after withdraw"
        );
        assertEq(investedAmount, 0, "Recipient invested amount mismatch");
        assertEq(totalSharesAfter, 0, "Recipient total shares mismatch after withdrawal");

        // Additional checks
        assertEq(tokenInBalanceAfter, expectedWithdrawal, "Incorrect asset amount returned");
    }

    function _transferInRewards(uint256 _amount) internal {
        address defaultAdmin = strategy.stdeUSD().owner();

        address rewarder = vm.randomAddress();
        deal(deUSD, rewarder, _amount);

        vm.startPrank(defaultAdmin);
        strategy.stdeUSD().grantRole(keccak256("REWARDER_ROLE"), rewarder);
        vm.stopPrank();

        vm.startPrank(rewarder, rewarder);
        IERC20(deUSD).approve(tokenOut, _amount);

        strategy.stdeUSD().transferInRewards(_amount);
        vm.stopPrank();
    }
}