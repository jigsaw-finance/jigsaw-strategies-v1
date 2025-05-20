// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";
import "../fixtures/StrategyTestUtils.t.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ReservoirSavingStrategy } from "../../src/reservoir/ReservoirSavingStrategy.sol";
import { ReservoirSavingStrategyV2 } from "../../src/reservoir/ReservoirSavingStrategyV2.sol";

address constant RESERVOIR_CI = 0x04716DB62C085D9e08050fcF6F7D775A03d07720;
address constant RESERVOIR_PSM = 0x4809010926aec940b550D34a46A52739f996D75D;
address constant RESERVOIR_SM = 0x5475611Dffb8ef4d697Ae39df9395513b6E947d7;

contract ReservoirSavingStrategyV2UpgradeTest is Test, BasicContractsFixture, StrategyTestUtils {
    // Mainnet USDC
    address internal USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Reservoir stablecoin (rUSD)
    address internal rUSD = 0x09D4214C03D01F49544C0448DBE3A27f768F2b34;
    // Reservoir saving coin (srUSD)
    address internal srUSD = 0x738d1115B90efa71AE468F1287fc864775e23a31;

    address tokenIn;
    address tokenOut;

    ReservoirSavingStrategy internal strategy;

    function setUp() public {
        init();
    }

    // Test reinitialization
    function test_reinitialization_reservoir() public {
        tokenIn = USDC;
        tokenOut = srUSD;
        _deploy();
        _validate_reinitialization();
    }

    // Tests if withdrawal works correctly when using USDC for deposit
    function test_reservoirSaving_claimInvestment_when_USDC_upgrade() public {
        tokenIn = USDC;
        tokenOut = srUSD;

        _deploy();

        address user = address(22);
        uint256 amount = 1000e6;
        address userHolding = initiateUser(user, tokenIn, amount);

        deal(tokenOut, userHolding, 0);

        // Invest into the tested strategy via strategyManager
        vm.prank(user, user);

        strategyManager.invest(tokenIn, address(strategy), amount, 0, "");

        (uint256 investedAmountBefore, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);

        // Upgrade to V2
        _upgradeToV2();

        skip(100 days);

        vm.prank(user, user);

        (uint256 assetAmount, uint256 tokenInAmount,, uint256 fee) = strategyManager.claimInvestment({
            _holding: userHolding,
            _token: tokenIn,
            _strategy: address(strategy),
            _shares: totalShares,
            _data: ""
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
        // 1.
        assertEq(tokenInBalanceAfter, assetAmount, "Holding balance after withdraw is wrong");
        // 2.
        assertApproxEqAbs(IERC20(tokenOut).balanceOf(userHolding), 0, 1, "Holding token out balance wrong");
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
        assertApproxEqAbs(fee, IERC20(tokenIn).balanceOf(manager.feeAddress()), 1, "Fee address fee amount wrong");

        // Additional checks
        assertEq(assetAmount, expectedWithdrawal, "Incorrect asset amount returned");
        assertEq(tokenInAmount, investedAmountBefore, "Incorrect tokenInAmount returned");
    }

    // Tests if deposit works correctly when using rUSD for deposit
    function test_reservoirSaving_deposit_when_rUSD(address user, uint256 _amount) public notOwnerNotZero(user) {
        tokenIn = rUSD;
        tokenOut = srUSD;

        _deploy();

        uint256 amount = bound(_amount, 1e6, 10_000e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        uint256 tokenOutBalanceBefore = IERC20(tokenOut).balanceOf(userHolding);
        uint256 expectedSrusd = ISM(RESERVOIR_SM).previewMint(amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) =
            strategyManager.invest(tokenIn, address(strategy), amount, 0, "");

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
        // 2.
        assertEq(tokenOutBalanceAfter, expectedSrusd, "Holding token out balance wrong");
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
    }

    // Tests if withdrawal works correctly when using rUSD for deposit
    function test_reservoirSaving_claimInvestment_when_rUSD(
        address user,
        uint256 _amount
    ) public notOwnerNotZero(user) {
        tokenIn = rUSD;
        tokenOut = srUSD;

        _deploy();

        uint256 amount = bound(_amount, 1e6, 10_000e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        deal(tokenOut, userHolding, 0);

        // Invest into the tested strategy via strategyManager
        vm.prank(user, user);

        strategyManager.invest(tokenIn, address(strategy), amount, 0, "");

        (uint256 investedAmountBefore, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);

        skip(100 days);

        uint256 fee = _getFeeAbsolute(
            totalShares * ISM(RESERVOIR_SM).currentPrice() / 1e8 * 1e6 / (1e6 + ISM(RESERVOIR_SM).redeemFee())
                - investedAmountBefore,
            manager.performanceFee()
        );

        vm.prank(user, user);

        (uint256 assetAmount, uint256 tokenInAmount,,) = strategyManager.claimInvestment({
            _holding: userHolding,
            _token: tokenIn,
            _strategy: address(strategy),
            _shares: totalShares,
            _data: ""
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
        // 1.
        assertEq(tokenInBalanceAfter, assetAmount, "Holding balance after withdraw is wrong");
        // 2.
        assertApproxEqAbs(IERC20(tokenOut).balanceOf(userHolding), 0, 1, "Holding token out balance wrong");
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
        assertApproxEqAbs(fee, IERC20(tokenIn).balanceOf(manager.feeAddress()), 1, "Fee address fee amount wrong");

        // Additional checks
        assertEq(assetAmount, expectedWithdrawal, "Incorrect asset amount returned");
        assertEq(tokenInAmount, investedAmountBefore, "Incorrect tokenInAmount returned");
    }

    // Upgrade ReservoirSavingStrategy to ReservoirSavingStrategyV2
    function _upgradeToV2() internal override {
        vm.startPrank(OWNER, OWNER);

        // Deploy the new implementation of ReservoirSavingStrategyV2
        address strategyV2Implementation = address(new ReservoirSavingStrategyV2());

        // Perform the upgrade
        bytes memory data = abi.encodeCall(
            ReservoirSavingStrategyV2.initialize,
            ReservoirSavingStrategyV2.InitializerParams({ feeManager: address(feeManager) })
        );

        strategy.upgradeToAndCall(strategyV2Implementation, data);
        vm.stopPrank();
    }

    function _getStrategyStateVariables() internal view override returns (StrategyStateVariables memory) {
        return StrategyStateVariables({
            owner: strategy.owner(),
            manager: address(strategy.manager()),
            rewardToken: strategy.rewardToken(),
            tokenIn: strategy.tokenIn(),
            tokenOut: strategy.tokenOut(),
            sharesDecimals: strategy.sharesDecimals()
        });
    }

    // -- Utilities --
    function _deploy() internal {
        tokenIn = rUSD;
        tokenOut = srUSD;

        address strategyImplementation = address(new ReservoirSavingStrategy());
        bytes memory data = abi.encodeCall(
            ReservoirSavingStrategy.initialize,
            ReservoirSavingStrategy.InitializerParams({
                owner: OWNER,
                manager: address(manager),
                creditEnforcer: RESERVOIR_CI,
                pegStabilityModule: RESERVOIR_PSM,
                savingModule: RESERVOIR_SM,
                rUSD: rUSD,
                stakerFactory: address(stakerFactory),
                jigsawRewardToken: jRewards,
                jigsawRewardDuration: 60 days,
                tokenIn: tokenIn,
                tokenOut: tokenOut
            })
        );

        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = ReservoirSavingStrategy(proxy);

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
            ISharesRegistry.RegistryConfig({ collateralizationRate: 90_000, liquidationBuffer: 0, liquidatorBonus: 0 })
        );
        stablesManager.registerOrUpdateShareRegistry(address(tokenInSharesRegistry), address(tokenIn), true);
        registries[address(tokenIn)] = address(tokenInSharesRegistry);

        vm.stopPrank();
    }
}

interface ISM {
    function previewMint(
        uint256 amount
    ) external view returns (uint256);
    function previewRedeem(
        uint256 amount
    ) external view returns (uint256);
    function currentPrice() external view returns (uint256);
    function redeemFee() external view returns (uint256);
}
