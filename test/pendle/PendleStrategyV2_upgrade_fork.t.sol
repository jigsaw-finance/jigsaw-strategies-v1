// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";
import "../fixtures/StrategyTestUtils.t.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@pendle/interfaces/IPAllActionV3.sol";
import { IPMarket, IPYieldToken, IStandardizedYield } from "@pendle/interfaces/IPMarket.sol";
import { IPSwapAggregator } from "@pendle/router/swap-aggregator/IPSwapAggregator.sol";

import { PendleStrategy } from "../../src/pendle/PendleStrategy.sol";
import { PendleStrategyV2 } from "../../src/pendle/PendleStrategyV2.sol";

address constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;
address constant PENDLE_MARKET = 0x58612beB0e8a126735b19BB222cbC7fC2C162D2a; // pufETH pendle market address

contract PendleStrategyV2UpgradeTest is Test, BasicContractsFixture, StrategyTestUtils {
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

    TokenOutput internal emptyTokenOutput;

    // DefaultApprox means no off-chain preparation is involved, more gas consuming (~ 180k gas)
    ApproxParams public defaultApprox =
        ApproxParams({ guessMin: 0, guessMax: type(uint256).max, guessOffchain: 0, maxIteration: 256, eps: 1e14 });

    function test_emptyLimit() public {
        vm.assertEq(keccak256(abi.encode(emptyLimit)), keccak256(abi.encode(emptyLimit)), "Empty limit is not empty");
        vm.assertEq(
            keccak256(abi.encode(emptyTokenOutput)),
            keccak256(abi.encode(emptyTokenOutput)),
            "emptyTokenOutput is not empty"
        );
        vm.assertEq(keccak256(abi.encode(emptySwap)), keccak256(abi.encode(emptySwap)), "emptySwap is not empty");
    }

    function setUp() public {
        init();

        address strategyImplementation = address(new PendleStrategy());
        bytes memory data = abi.encodeCall(
            PendleStrategy.initialize,
            PendleStrategy.InitializerParams({
                owner: OWNER,
                manager: address(manager),
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

    // Tests if withdrawal works correctly when authorized
    function test_pendle_withdraw_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 10e18);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy via strategyManager
        vm.startPrank(user, user);
        (uint256 tokenOutAmount, uint256 tokenInAmount) = strategyManager.invest({
            _token: tokenIn,
            _strategy: address(strategy),
            _amount: amount,
            _minSharesAmountOut: 0,
            _data: abi.encode(
                strategy.getMinAllowedLpOut(amount), // minLpOut
                defaultApprox, // _guessPtReceivedFromSy
                TokenInput({
                    tokenIn: tokenIn,
                    netTokenIn: amount,
                    tokenMintSy: tokenIn,
                    pendleSwap: address(0),
                    swapData: emptySwap
                }),
                emptyLimit
            )
        });

        skip(100 days);

        // Upgrade to V2
        _upgradeToV2();

        vm.startPrank(user, user);
        (,, int256 yield, uint256 fee) = strategyManager.claimInvestment({
            _holding: userHolding,
            _token: tokenIn,
            _strategy: address(strategy),
            _shares: tokenOutAmount,
            _data: abi.encode(
                TokenOutput({
                    tokenOut: tokenIn,
                    minTokenOut: strategy.getMinAllowedTokenOut(tokenOutAmount), // minTokenOut
                    tokenRedeemSy: tokenIn,
                    pendleSwap: address(0),
                    swapData: emptySwap
                }),
                emptyLimit
            )
        });

        vm.stopPrank();

        (uint256 investedAmount, uint256 totalSharesAfter) = strategy.recipients(userHolding);

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
        assertEq(IERC20(tokenIn).balanceOf(userHolding), amount + uint256(yield), "Withdraw amount wrong");
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
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
    }

    function test_pendle_claimRewards_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 10e18);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy via strategyManager
        vm.startPrank(user, user);
        strategyManager.invest(
            tokenIn,
            address(strategy),
            amount,
            0,
            abi.encode(
                strategy.getMinAllowedLpOut(amount),
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

    // Upgrade PendleStrategy to PendleStrategyV2
    function _upgradeToV2() internal override {
        vm.startPrank(OWNER, OWNER);

        // Deploy the new implementation of PendleStrategyV2
        address strategyV2Implementation = address(new PendleStrategyV2());

        // Perform the upgrade
        bytes memory data = abi.encodeCall(
            PendleStrategyV2.initialize, PendleStrategyV2.InitializerParams({ feeManager: address(feeManager) })
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
