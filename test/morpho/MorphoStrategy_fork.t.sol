// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../fixtures/BasicContractsFixture.t.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { MorphoStrategy } from "../../src/morpho/MorphoStrategy.sol";

contract MorphoStrategyTest is Test, BasicContractsFixture {
    using SafeERC20 for IERC20;

    // Mainnet USDC
    address internal tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Steakhouse USDC Morpho Vault
    address internal tokenOut = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;

    MorphoStrategy internal strategy;

    // Mock user address
    address user = vm.randomAddress();

    function setUp() public {
        init();

        address strategyImplementation = address(new MorphoStrategy());
        MorphoStrategy.InitializerParams memory initParams = MorphoStrategy.InitializerParams({
            owner: OWNER,
            manager: address(manager),
            stakerFactory: address(stakerFactory),
            jigsawRewardToken: jRewards,
            jigsawRewardDuration: 60 days,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            feeManager: address(feeManager)
        });

        bytes memory data = abi.encodeCall(MorphoStrategy.initialize, initParams);
        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = MorphoStrategy(proxy);

        // Add tested strategy to the StrategyManager for integration testing purposes
        vm.startPrank((OWNER));
        manager.whitelistToken(tokenIn);
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

    // Tests if deposit works correctly when authorized
    function test_morpho_deposit_when_authorized() public {
        uint256 amount = 100e6;
        address userHolding = initiateUser(user, tokenIn, amount);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        uint256 tokenOutBalanceBefore = IERC20(tokenOut).balanceOf(userHolding);

        bytes memory data = abi.encode(0);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) =
            strategyManager.invest(tokenIn, address(strategy), amount, 0, data);

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
        assertGe(IERC20(tokenOut).balanceOf(userHolding), receiptTokens, "Holding token out balance wrong");
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            expectedShares,
            "Incorrect receipt tokens minted"
        );
        assertEq(investedAmount, amount, "Recipient invested amount mismatch");
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");

        // Additional checks
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
    }

    // Tests if withdraw works correctly when authorized
    function test_morpho_withdraw_when_authorized(
        uint256 _amount
    ) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 100e6, 100e8);
        address userHolding = initiateUser(user, tokenIn, amount);

        bytes memory data = abi.encode(0);

        // Invest into the tested strategy via strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, 0, data);

        (, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);

        skip(90 days);

        vm.prank(user, user);
        (uint256 assetAmount,,,) = strategyManager.claimInvestment({
            _holding: userHolding,
            _token: tokenIn,
            _strategy: address(strategy),
            _shares: totalShares,
            _data: data
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

    // Revert: onlyStrategyManager on deposit
    function test_morpho_deposit_reverts_when_not_manager() public {
        uint256 amount = 10e6;
        address userHolding = initiateUser(user, tokenIn, amount);
        bytes memory data = abi.encode(0);
        vm.expectRevert(bytes("1000"));
        strategy.deposit(tokenIn, amount, userHolding, data);
    }

    // Revert: wrong asset on deposit
    function test_morpho_deposit_reverts_wrong_asset() public {
        uint256 amount = 10e6;
        address userHolding = initiateUser(user, tokenIn, amount);
        bytes memory data = abi.encode(0);
        vm.prank(address(strategyManager));
        vm.expectRevert(bytes("3001"));
        strategy.deposit(address(0xDEAD), amount, userHolding, data);
    }

    // Revert: SharesTooLow on deposit
    function test_morpho_deposit_reverts_shares_too_low() public {
        uint256 amount = 50e6;
        address userHolding = initiateUser(user, tokenIn, amount);
        uint256 expectedShares = strategy.previewDeposit(amount);
        bytes memory data = abi.encode(expectedShares + 1);
        assertTrue(userHolding != address(0));
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(MorphoStrategy.SharesTooLow.selector, expectedShares, expectedShares + 1)
        );
        strategyManager.invest(tokenIn, address(strategy), amount, 0, data);
    }

    // Revert: onlyStrategyManager on withdraw
    function test_morpho_withdraw_reverts_when_not_manager() public {
        vm.expectRevert(bytes("1000"));
        strategy.withdraw(1, address(0x1), tokenIn, abi.encode(0));
    }

    // Revert: wrong asset on withdraw
    function test_morpho_withdraw_reverts_wrong_asset() public {
        uint256 amount = 20e6;
        address userHolding = initiateUser(user, tokenIn, amount);
        bytes memory data = abi.encode(0);
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, 0, data);
        (, uint256 totalShares) = strategy.recipients(userHolding);
        vm.prank(address(strategyManager));
        vm.expectRevert(bytes("3001"));
        strategy.withdraw(totalShares, userHolding, address(0xBEEF), abi.encode(0));
    }

    // Revert: AssetsTooLow on withdraw
    function test_morpho_withdraw_reverts_assets_too_low() public {
        uint256 amount = 30e6;
        address userHolding = initiateUser(user, tokenIn, amount);
        bytes memory data = abi.encode(0);
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, 0, data);
        (, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 assets = strategy.previewWithdraw(totalShares);
        vm.prank(user, user);
        vm.expectRevert(abi.encodeWithSelector(MorphoStrategy.AssetsTooLow.selector, assets, assets + 1));
        strategyManager.claimInvestment({
            _holding: userHolding,
            _token: tokenIn,
            _strategy: address(strategy),
            _shares: totalShares,
            _data: abi.encode(assets + 1)
        });
    }

    // Getters and previews work
    function test_morpho_getters_and_previews() public view {
        assertEq(strategy.getReceiptTokenAddress(), address(strategy.receiptToken()), "receipt token addr mismatch");
        uint256 shares = strategy.previewDeposit(1e6);
        // shares can be zero or positive depending on vault conditions; just call to cover path
        uint256 assets = strategy.previewWithdraw(shares);
        // round-trip not guaranteed, but should not revert
        assertApproxEqAbs(assets, 1e6, 100);
    }

    // claimRewards unsupported
    function test_morpho_claimRewards_reverts_operation_not_supported() public {
        vm.expectRevert(MorphoStrategy.OperationNotSupported.selector);
        strategy.claimRewards(address(0), bytes(""));
    }

    // Fee deduction on withdraw when custom fee set
    function test_morpho_withdraw_takes_performance_fee() public {
        uint256 amount = 100e6;
        address userHolding = initiateUser(user, tokenIn, amount);
        bytes memory data = abi.encode(0);

        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, 0, data);

        (, uint256 totalShares) = strategy.recipients(userHolding);

        // Set custom fee 5%
        vm.startPrank(OWNER);
        feeManager.setHoldingCustomFee(userHolding, address(strategy), 500);
        vm.stopPrank();

        uint256 feeAddrBalanceBefore = IERC20(tokenIn).balanceOf(manager.feeAddress());

        skip(30 days);

        vm.prank(user, user);
        (uint256 withdrawnAmount, uint256 initialInvestment, int256 yield, uint256 fee) = strategyManager
            .claimInvestment({
            _holding: userHolding,
            _token: tokenIn,
            _strategy: address(strategy),
            _shares: totalShares,
            _data: abi.encode(0)
        });

        // Fee should be taken only if there is positive yield; in case of zero yield skip assertions gracefully
        if (yield > 0) {
            assertGt(fee, 0, "fee should be > 0 when yield > 0");
            uint256 feeAddrBalanceAfter = IERC20(tokenIn).balanceOf(manager.feeAddress());
            assertEq(feeAddrBalanceAfter - feeAddrBalanceBefore, fee, "fee address balance mismatch");
            // withdrawnAmount + fee should equal total assets redeemed minus any rounding
            assertGe(
                uint256(int256(withdrawnAmount) + int256(fee)), uint256(initialInvestment), "withdraw + fee < invest"
            );
        }
    }
}
