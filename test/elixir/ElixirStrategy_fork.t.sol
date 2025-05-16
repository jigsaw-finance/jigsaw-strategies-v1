// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma abicoder v2;

import "../fixtures/BasicContractsFixture.t.sol";

import { StdStorage, stdStorage } from "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ElixirStrategy } from "../../src/elixir/ElixirStrategy.sol";
import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";
import { SampleOracleUniswap } from "@jigsaw/test/utils/mocks/SampleOracleUniswap.sol";

contract ElixirStrategyTest is Test, BasicContractsFixture {
    using SafeERC20 for IERC20;

    // Mainnet USDT
    address internal tokenIn = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // sdeUSD token
    address internal tokenOut = 0x5C5b196aBE0d54485975D1Ec29617D42D9198326;

    // Mainnet USDC
    address internal USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // deUSD token
    address internal deUSD = 0x15700B564Ca08D9439C58cA5053166E8317aa138;

    address internal uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address internal DEUSD_USDC_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6; // deUSD/USDT pool

    address internal USDC_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6; // USDT/USDC pool

    address internal user = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    uint24 internal constant poolFee = 100;

    uint256 internal DECIMAL_DIFF = 1e12;

    ElixirStrategy internal strategy;

    function setUp() public {
        init();

        address[] memory pools = new address[](2);

        pools[0] = USDC_POOL;
        pools[1] = DEUSD_USDC_POOL;

        address strategyImplementation = address(new ElixirStrategy());
        ElixirStrategy.InitializerParams memory initParams = ElixirStrategy.InitializerParams({
            owner: OWNER,
            manager: address(manager),
            stakerFactory: address(stakerFactory),
            jigsawRewardToken: jRewards,
            jigsawRewardDuration: 60 days,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            deUSD: deUSD,
            uniswapRouter: uniswapRouter,
            oracle: address(new SampleOracle()),
            initialPools: pools,
            feeManager: address(feeManager)
        });

        bytes memory data = abi.encodeCall(ElixirStrategy.initialize, initParams);
        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = ElixirStrategy(proxy);

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
    function test_elixir_deposit_when_authorized(
        uint256 _amount
    ) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 1e8);
        address userHolding = initiateUser(user, tokenIn, amount);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        uint256 tokenOutBalanceBefore = IERC20(tokenOut).balanceOf(userHolding);

        bytes memory data = abi.encode(
            amount * DECIMAL_DIFF, // amountOutMinimum
            uint256(block.timestamp), // deadline
            abi.encodePacked(tokenIn, poolFee, USDC, poolFee, deUSD)
        );

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
        assertGe(
            IERC20(tokenOut).balanceOf(userHolding),
            strategy.getAllowedAmountOutMin(amount, ElixirStrategy.SwapDirection.FromTokenIn),
            "Holding token out balance wrong"
        );
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
            strategy.sdeUSD().convertToShares(amount * DECIMAL_DIFF),
            0.01e18,
            "Wrong balance in Elixir after stake"
        );
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
    }

    // Tests if withdraw works correctly when authorized
    function test_elixir_withdraw_when_authorized(
        uint256 _amount
    ) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 1e8);
        address userHolding = initiateUser(user, tokenIn, amount);

        bytes memory data = abi.encode(
            amount * DECIMAL_DIFF, // amountOutMinimum
            uint256(block.timestamp), // deadline
            abi.encodePacked(tokenIn, poolFee, USDC, poolFee, deUSD)
        );

        // Invest into the tested strategy via strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, 0, data);

        (, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);

        _transferInRewards(100_000e18);
        skip(90 days);

        vm.prank(user, user);
        strategy.cooldown(userHolding, totalShares);
        skip(7 days);

        bytes memory dataClaimInvest = abi.encode(
            amount, // amountOutMinimum
            uint256(block.timestamp), // deadline
            abi.encodePacked(deUSD, poolFee, USDC, poolFee, tokenIn)
        );

        vm.prank(user, user);
        (uint256 assetAmount,,,) = strategyManager.claimInvestment({
            _holding: userHolding,
            _token: tokenIn,
            _strategy: address(strategy),
            _shares: totalShares,
            _data: dataClaimInvest
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

    function test_elixir_deposit_reverts_when_invalidSwapPathLength() public {
        uint256 amount = 10e6;
        initiateUser(user, tokenIn, amount);

        bytes memory invalidData = abi.encode(amount, block.timestamp + 1 days, bytes("short"));

        deal(tokenIn, user, amount);

        vm.expectRevert(ElixirStrategy.InvalidSwapPathLength.selector);
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, 0, invalidData);
    }

    function test_elixir_updatesSlippagePercentageCorrectly() public {
        uint256 newSlippage = 300;
        vm.prank(OWNER);
        strategy.setSlippagePercentage(newSlippage);

        assertEq(strategy.allowedSlippagePercentage(), newSlippage);
    }

    function test_elixir_revertsOnExceedingSlippageLimit() public {
        uint256 invalidSlippage = 20_000; // Exceeds SLIPPAGE_PRECISION

        vm.prank(OWNER, OWNER);
        vm.expectRevert(bytes("3002"));
        strategy.setSlippagePercentage(invalidSlippage);
    }

    function test_elixir_revertsOnClaimRewards() public {
        vm.prank(user, user);
        vm.expectRevert(ElixirStrategy.OperationNotSupported.selector);
        strategy.claimRewards(address(0), "");
    }

    function _transferInRewards(
        uint256 _amount
    ) internal {
        ISdeUsd sdeUSD = ISdeUsd(address(strategy.sdeUSD()));
        address defaultAdmin = sdeUSD.owner();

        address rewarder = vm.randomAddress();
        deal(deUSD, rewarder, _amount);

        vm.startPrank(defaultAdmin);
        sdeUSD.grantRole(keccak256("REWARDER_ROLE"), rewarder);
        vm.stopPrank();

        vm.startPrank(rewarder, rewarder);
        IERC20(deUSD).approve(tokenOut, _amount);

        sdeUSD.transferInRewards(_amount);
        vm.stopPrank();
    }
}

interface ISdeUsd is IERC4626 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when the rewards are received
    event RewardsReceived(uint256 amount);
    /// @notice Event emitted when the balance from an FULL_RESTRICTED_STAKER_ROLE user are redistributed
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);

    /// @notice Event emitted when cooldown duration updates
    event CooldownDurationUpdated(uint24 previousDuration, uint24 newDuration);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @notice Error emitted shares or assets equal zero.
    error InvalidAmount();
    /// @notice Error emitted when owner attempts to rescue deUSD tokens.
    error InvalidToken();
    /// @notice Error emitted when a small non-zero share amount remains, which risks donations attack
    error MinSharesViolation();
    /// @notice Error emitted when owner is not allowed to perform an operation
    error OperationNotAllowed();
    /// @notice Error emitted when there is still unvested amount
    error StillVesting();
    /// @notice Error emitted when owner or blacklist manager attempts to blacklist owner
    error CantBlacklistOwner();
    /// @notice Error emitted when the zero address is given
    error InvalidZeroAddress();

    /// @notice Error emitted when the shares amount to redeem is greater than the shares balance of the owner
    error ExcessiveRedeemAmount();
    /// @notice Error emitted when the shares amount to withdraw is greater than the shares balance of the owner
    error ExcessiveWithdrawAmount();
    /// @notice Error emitted when cooldown value is invalid
    error InvalidCooldown();
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function cooldownDuration() external returns (uint24);

    function owner() external returns (address);

    function transferInRewards(
        uint256 amount
    ) external;

    function rescueTokens(address token, uint256 amount, address to) external;

    function getUnvestedAmount() external view returns (uint256);

    function cooldownAssets(
        uint256 assets
    ) external returns (uint256 shares);

    function cooldownShares(
        uint256 shares
    ) external returns (uint256 assets);

    function unstake(
        address receiver
    ) external;

    function setCooldownDuration(
        uint24 duration
    ) external;

    function withdraw(uint256 assets, address receiver, address _owner) external returns (uint256);

    function grantRole(bytes32 role, address account) external;
}
