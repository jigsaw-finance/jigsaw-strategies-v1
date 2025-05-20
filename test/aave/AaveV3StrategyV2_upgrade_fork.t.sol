// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "../fixtures/BasicContractsFixture.t.sol";
import "../fixtures/StrategyTestUtils.t.sol";

import { AaveV3Strategy } from "../../src/aave/AaveV3Strategy.sol";
import { AaveV3StrategyV2 } from "../../src/aave/AaveV3StrategyV2.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";
import { IAToken } from "@aave/v3-core/interfaces/IAToken.sol";
import { IPool } from "@aave/v3-core/interfaces/IPool.sol";
import { IRewardsController } from "@aave/v3-periphery/rewards/interfaces/IRewardsController.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AaveV3StrategyV2UpgradeTest is Test, BasicContractsFixture, StrategyTestUtils {
    AaveV3Strategy internal strategy;

    address internal lendingPool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal rewardsController = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address internal emissionManager = 0x223d844fc4B006D67c0cDbd39371A9F73f69d974;

    // Mainnet usdc
    address internal tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Aave interest bearing aUSDC
    address internal tokenOut = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    function setUp() public {
        init();

        address strategyImplementation = address(new AaveV3Strategy());
        bytes memory data = abi.encodeCall(
            AaveV3Strategy.initialize,
            AaveV3Strategy.InitializerParams({
                owner: OWNER,
                manager: address(manager),
                stakerFactory: address(stakerFactory),
                lendingPool: lendingPool,
                rewardsController: rewardsController,
                rewardToken: address(0),
                jigsawRewardToken: jRewards,
                jigsawRewardDuration: 60 days,
                tokenIn: tokenIn,
                tokenOut: tokenOut
            })
        );

        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = AaveV3Strategy(proxy);

        // Add tested strategy to the StrategyManager for integration testing purposes
        vm.startPrank(OWNER);
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

    // Test reinitialization
    function test_reinitialization() public {
        _validate_reinitialization();
    }

    // Tests if withdraw works correctly for v2
    function test_withdraw_aave_v2(uint256 _amount, address user) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 10e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, 0, abi.encode("random ref"));

        (, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        (uint256 investedAmountBefore,) = strategy.recipients(userHolding);

        skip(100 days);

        uint256 fee =
            _getFeeAbsolute(IERC20(tokenOut).balanceOf(userHolding) - investedAmountBefore, manager.performanceFee());

        // Upgrade to V2
        _upgradeToV2();

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
        assertEq(IAToken(tokenOut).scaledBalanceOf(userHolding), 0, "Holding token out balance wrong");
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
        assertEq(assetAmount, expectedWithdrawal, "Incorrect asset amount returned");
        assertEq(tokenInAmount, investedAmountBefore, "Incorrect tokenInAmount returned");
    }

    // Tests if withdraw works correctly for v2
    function test_custom_fee_withdraw_aave_v2(uint256 _amount, address user) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 10e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, 0, abi.encode("random ref"));

        (, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        (uint256 investedAmountBefore,) = strategy.recipients(userHolding);

        // Upgrade to V2
        _upgradeToV2();

        AaveV3StrategyV2 strategyV2 = AaveV3StrategyV2(address(strategy));

        uint256 customFee = 2000;
        vm.startPrank(OWNER);
        strategyV2.feeManager().setHoldingCustomFee(userHolding, address(strategy), customFee);
        vm.stopPrank();

        skip(100 days);

        uint256 fee = _getFeeAbsolute(IERC20(tokenOut).balanceOf(userHolding) - investedAmountBefore, customFee);

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
        assertEq(IAToken(tokenOut).scaledBalanceOf(userHolding), 0, "Holding token out balance wrong");
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
        assertEq(assetAmount, expectedWithdrawal, "Incorrect asset amount returned");
        assertEq(tokenInAmount, investedAmountBefore, "Incorrect tokenInAmount returned");
    }

    // Upgrade AaveV3Strategy to AaveV3StrategyV2
    function _upgradeToV2() internal override {
        vm.startPrank(OWNER, OWNER);

        // Deploy the new implementation of AaveV3StrategyV2
        address strategyV2Implementation = address(new AaveV3StrategyV2());

        // Perform the upgrade
        bytes memory data = abi.encodeCall(
            AaveV3StrategyV2.initialize, AaveV3StrategyV2.InitializerParams({ feeManager: address(feeManager) })
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
}
