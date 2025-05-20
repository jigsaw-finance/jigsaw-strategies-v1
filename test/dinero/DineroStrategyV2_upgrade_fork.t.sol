// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";
import "../fixtures/StrategyTestUtils.t.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { DineroStrategy } from "../../src/dinero/DineroStrategy.sol";
import { DineroStrategyV2 } from "../../src/dinero/DineroStrategyV2.sol";
import { IAutoPxEth } from "../../src/dinero/interfaces/IAutoPxEth.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";

address constant PX_ETH = 0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6;
IPirexEth constant PIREX_ETH = IPirexEth(0xD664b74274DfEB538d9baC494F3a4760828B02b0);
IAutoPxEth constant AUTO_PIREX_ETH = IAutoPxEth(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6);

contract DineroStrategyV2UpgradeTest is Test, BasicContractsFixture, StrategyTestUtils {
    // Mainnet wETH
    address internal tokenIn = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // apxETH token
    address internal tokenOut = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;

    DineroStrategy internal strategy;

    function setUp() public {
        init();

        address strategyImplementation = address(new DineroStrategy());
        DineroStrategy.InitializerParams memory initParams = DineroStrategy.InitializerParams({
            owner: OWNER,
            manager: address(manager),
            stakerFactory: address(stakerFactory),
            pirexEth: address(PIREX_ETH),
            autoPirexEth: address(AUTO_PIREX_ETH),
            jigsawRewardToken: jRewards,
            jigsawRewardDuration: 60 days,
            tokenIn: tokenIn,
            tokenOut: tokenOut
        });

        bytes memory data = abi.encodeCall(DineroStrategy.initialize, initParams);
        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = DineroStrategy(payable(proxy));

        // Add tested strategy to the StrategyManager for integration testing purposes
        vm.startPrank((OWNER));
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

    // Tests if withdraw works correctly when authorized
    function test_dinero_withdraw_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 10e18);
        address userHolding = initiateUser(user, tokenIn, amount, false);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, 0, "");

        (uint256 investedAmountBefore, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);

        skip(100 days);

        // Upgrade to V2
        _upgradeToV2();

        // Increase the balance of the autoPxEth with pxETH
        uint256 addedRewards = 1e22;
        deal(address(PX_ETH), address(AUTO_PIREX_ETH), addedRewards);
        // Updated rewards state variable in autoPxEth contract
        vm.store(address(AUTO_PIREX_ETH), bytes32(uint256(14)), bytes32(uint256(addedRewards)));

        // Pirex ETH takes fee for instant redemption
        uint256 postRedemptionFeeAssetAmt = subtractPercent(
            AUTO_PIREX_ETH.previewRedeem(totalShares), PIREX_ETH.fees(IPirexEth.Fees.InstantRedemption) / 1000
        );

        // Compute Jigsaw's performance fee
        uint256 fee = investedAmountBefore >= postRedemptionFeeAssetAmt
            ? 0
            : _getFeeAbsolute(postRedemptionFeeAssetAmt - investedAmountBefore, manager.performanceFee());

        vm.prank(user, user);
        (uint256 assetAmount,,,) = strategyManager.claimInvestment({
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
        assertEq(tokenInBalanceAfter, assetAmount, "Holding balance after withdraw is wrong");
        assertEq(IERC20(tokenOut).balanceOf(userHolding), 0, "Holding token out balance wrong");
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            0,
            "Incorrect receipt tokens after withdraw"
        );
        assertEq(investedAmount, 0, "Recipient invested amount mismatch");
        assertEq(totalSharesAfter, 0, "Recipient total shares mismatch after withdrawal");
        assertEq(fee, IERC20(tokenIn).balanceOf(manager.feeAddress()), "Fee address fee amount wrong");

        // Additional checks
        assertEq(tokenInBalanceAfter, expectedWithdrawal, "Incorrect asset amount returned");
    }

    // percent == 0.1%
    function subtractPercent(uint256 value, uint256 percent) public pure returns (uint256) {
        uint256 deduction = (value * percent) / 1000; // 0.5% is 5/1000
        return value - deduction;
    }

    // Upgrade DineroStrategy to DineroStrategyV2
    function _upgradeToV2() internal override {
        vm.startPrank(OWNER, OWNER);

        // Deploy the new implementation of DineroStrategyV2
        address strategyV2Implementation = address(new DineroStrategyV2());

        // Perform the upgrade
        bytes memory data = abi.encodeCall(
            DineroStrategyV2.initialize, DineroStrategyV2.InitializerParams({ feeManager: address(feeManager) })
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

interface IPirexEth {
    // Configurable fees
    enum Fees {
        // Fee type for deposit
        Deposit,
        // Fee type for redemption
        Redemption,
        // Fee type for instant redemption
        InstantRedemption
    }

    /**
     * @notice Retrieves the fee percentage for a specific operation type.
     * @param feeType The type of fee (e.g., Deposit, Redemption, InstantRedemption).
     * @return feePercentage The fee percentage corresponding to the provided fee type.
     *         The value is scaled by 1,000,000 (e.g., 5000 represents 0.5%).
     */
    function fees(
        Fees feeType
    ) external view returns (uint32);
}
