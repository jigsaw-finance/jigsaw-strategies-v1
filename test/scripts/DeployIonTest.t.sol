// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";

import { DeployStaker } from "script/deployment/0_DeployStaker.s.sol";
import { DeployIonImpl } from "script/deployment/ion/1_DeployIonImpl.s.sol";
import { DeployIonProxy } from "script/deployment/ion/2_DeployIonProxy.s.sol";

import { IonStrategy } from "../../src/ion/IonStrategy.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";
import { IStakerLight } from "../../src/staker/interfaces/IStakerLight.sol";

IIonPool constant ION_POOL = IIonPool(0x0000000000eaEbd95dAfcA37A39fd09745739b78);
IWhitelist constant ION_WHITELIST = IWhitelist(0x7E317f99aA313669AaCDd8dB3927ff3aCB562dAD);

contract DeployIonTest is Test, BasicContractsFixture {
    DeployIonProxy internal ionDeployer;
    // Mainnet wstETH
    address internal tokenIn = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    // Ion iweETH-wstETH token is the same as the pool due to Vault architecture
    address internal tokenOut = address(ION_POOL);

    IonStrategy internal strategy;

    function setUp() public {
        init();

        DeployIonImpl implDeployer = new DeployIonImpl();
        address implementation = implDeployer.run("my salt");

        ionDeployer = new DeployIonProxy();
        strategy = IonStrategy(
            ionDeployer.run({
                _implementation: implementation,
                _salt: 0x3412d07bef5d0dcdb942ac1765d0b8f19d8ca2c4cc7a66b902ba9b1ebc080040,
                _ionPool: address(ION_POOL),
                _rewardDuration: 60 days,
                _tokenIn: tokenIn,
                _tokenOut: tokenOut
            })
        );

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

        vm.startPrank(ION_POOL.owner());
        ION_POOL.updateIlkDebtCeiling(0, type(uint256).max);
        ION_POOL.updateSupplyCap(type(uint256).max);
        ION_WHITELIST.approveProtocolWhitelist(address(strategy));
        vm.stopPrank();
    }

    function test_ion_initialValues() public view {
        assertEq(address(strategy.owner()), ionDeployer.OWNER(), "Owner initialized wrong");
        assertEq(
            address(strategy.managerContainer()), ionDeployer.MANAGER_CONTAINER(), "Manager Container initialized wrong"
        );
        assertEq(address(strategy.ionPool()), address(ION_POOL), "Ion Pool initialized wrong");
        assertEq(strategy.tokenIn(), tokenIn, "tokenIn initialized wrong");
        assertEq(strategy.tokenOut(), tokenOut, "tokenOut initialized wrong");

        IStakerLight staker = strategy.jigsawStaker();

        assertEq(staker.rewardToken(), ionDeployer.jREWARDS(), "rewardToken initialized wrong");
        assertEq(staker.rewardsDuration(), 60 days, "rewardsDuration initialized wrong");
        assertEq(staker.periodFinish(), block.timestamp + 60 days, "periodFinish initialized wrong");
    }

    // Tests if deposit works correctly when authorized
    function test_ion_deposit_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 10e18);
        address userHolding = initiateUser(user, tokenIn, amount);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        uint256 ionBalanceBefore = IIonPool(tokenOut).normalizedBalanceOf(userHolding);

        // Invest into the tested strategy via strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) = strategyManager.invest(tokenIn, address(strategy), amount, "");

        (uint256 investedAmount, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 expectedShares = IIonPool(tokenOut).normalizedBalanceOf(userHolding) - ionBalanceBefore;

        /**
         * Expected changes after deposit
         * 1. Holding tokenIn balance =  balance - amount
         * 2. Holding tokenOut balance += ~amount
         * 3. Balance in ion += ~amount
         * 4. Staker receiptTokens balance += shares
         * 5. Strategy's invested amount  += amount
         * 6. Strategy's total shares  += shares
         */
        // 1.
        assertEq(IERC20(tokenIn).balanceOf(userHolding), tokenInBalanceBefore - amount, "Holding tokenIn balance wrong");
        // 2. and 3.
        assertApproxEqAbs(IIonPool(tokenOut).balanceOfUnaccrued(userHolding), amount, 2, "Holding ion balance wrong");
        // 4.
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            expectedShares,
            "Incorrect receipt tokens minted"
        );
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        // 5.
        assertEq(investedAmount, amount, "Recipient invested amount mismatch");
        // 6.
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
    }

    // Tests if withdraw works correctly when authorized
    function test_ion_withdraw_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e18, 10e18);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy via strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, "");

        (, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        (uint256 investedAmountBefore,) = strategy.recipients(userHolding);

        skip(100 days);

        uint256 fee =
            _getFeeAbsolute(IERC20(tokenOut).balanceOf(userHolding) - investedAmountBefore, manager.performanceFee());

        vm.prank(user, user);
        (uint256 assetAmount, uint256 tokenInAmount) = strategyManager.claimInvestment({
            _holding: userHolding,
            _strategy: address(strategy),
            _shares: totalShares,
            _asset: tokenIn,
            _data: ""
        });

        (uint256 investedAmount, uint256 totalSharesAfter) = strategy.recipients(userHolding);
        uint256 tokenInBalanceAfter = IERC20(tokenIn).balanceOf(userHolding);
        uint256 expectedWithdrawal = tokenInBalanceAfter - tokenInBalanceBefore;

        /**
         * Expected changes after withdrawal
         * 1. Holding's tokenIn balance += (totalInvested + yield) * shareRatio
         * 2. Holding's tokenOut balance -= shares
         * 3. Balance in ion -= (totalInvested + yield) * shareRatio
         * 4. Staker receiptTokens balance -= shares
         * 5. Strategy's invested amount  -= totalInvested * shareRatio
         * 6. Strategy's total shares  -= shares
         * 7. Fee address fee amount += yield * performanceFee
         */
        // 1.
        assertEq(tokenInBalanceAfter, assetAmount - fee, "Holding balance after withdraw is wrong");
        // 2. and 3.
        assertEq(IIonPool(tokenOut).balanceOfUnaccrued(userHolding), 0, "Holding ion balance wrong");
        // 4.
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            0,
            "Incorrect receipt tokens after withdraw"
        );
        // 5.
        assertEq(investedAmount, 0, "Recipient invested amount mismatch");
        // 6.
        assertEq(totalSharesAfter, 0, "Recipient total shares mismatch after withdrawal");
        // 7.
        assertEq(fee, IERC20(tokenIn).balanceOf(manager.feeAddress()), "Fee address fee amount wrong");

        // Additional checks
        assertEq(assetAmount - fee, expectedWithdrawal, "Incorrect asset amount returned");
        assertEq(tokenInAmount, investedAmountBefore, "Incorrect tokenInAmount returned");
    }
}

interface IIonPool {
    function withdraw(address receiverOfUnderlying, uint256 amount) external;
    function supply(address user, uint256 amount, bytes32[] calldata proof) external;
    function owner() external returns (address);
    function whitelist() external returns (address);
    function updateSupplyCap(
        uint256 newSupplyCap
    ) external;
    function updateIlkDebtCeiling(uint8 ilkIndex, uint256 newCeiling) external;
    function balanceOf(
        address user
    ) external view returns (uint256);
    function normalizedBalanceOf(
        address user
    ) external returns (uint256);
    function totalSupply() external view returns (uint256);
    function debt() external view returns (uint256);
    function supplyFactorUnaccrued() external view returns (uint256);
    function getIlkAddress(
        uint256 ilkIndex
    ) external view returns (address);
    function decimals() external view returns (uint8);
    function balanceOfUnaccrued(
        address user
    ) external view returns (uint256);
}

interface IWhitelist {
    /**
     * @notice Approves a protocol controlled address to bypass the merkle proof check.
     * @param addr The address to approve.
     */
    function approveProtocolWhitelist(
        address addr
    ) external;
}

contract Errors {
    // IonPool Errors
    error CeilingExceeded(uint256 newDebt, uint256 debtCeiling);
    error UnsafePositionChange(uint256 newTotalDebtInVault, uint256 collateral, uint256 spot);
    error UnsafePositionChangeWithoutConsent(uint8 ilkIndex, address user, address unconsentedOperator);
    error GemTransferWithoutConsent(uint8 ilkIndex, address user, address unconsentedOperator);
    error UseOfCollateralWithoutConsent(uint8 ilkIndex, address depositor, address unconsentedOperator);
    error TakingWethWithoutConsent(address payer, address unconsentedOperator);
    error VaultCannotBeDusty(uint256 amountLeft, uint256 dust);
    error ArithmeticError();
    error IlkAlreadyAdded(address ilkAddress);
    error IlkNotInitialized(uint256 ilkIndex);
    error DepositSurpassesSupplyCap(uint256 depositAmount, uint256 supplyCap);
    error MaxIlksReached();

    error InvalidIlkAddress();
    error InvalidWhitelist();

    // YieldOracle Errors

    error InvalidExchangeRate(uint256 ilkIndex);
    error InvalidIlkIndex(uint256 ilkIndex);
    error AlreadyUpdated();

    // PausableUpgradeable Errors
    error EnforcedPause();
    error ExpectedPause();
    error InvalidInitialization();
    error NotInitializing();

    // TransparentUpgradeableProxy Errors
    error ProxyDeniedAdminAccess();

    // AccessControl Errors
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error AccessControlBadConfirmation();

    // UniswapFlashswapDirectMintHandler
    error InvalidUniswapPool();
    error InvalidZeroLiquidityRegionSwap();
    error CallbackOnlyCallableByPool(address unauthorizedCaller);
    error OutputAmountNotReceived(uint256 amountReceived, uint256 amountRequired);

    error InvalidBurnAmount();
    error InvalidMintAmount();
    error InvalidUnderlyingAddress();
    error InvalidTreasuryAddress();
    error InvalidSender(address sender);
    error InvalidReceiver(address receiver);
    error InsufficientBalance(address account, uint256 balance, uint256 needed);
}
