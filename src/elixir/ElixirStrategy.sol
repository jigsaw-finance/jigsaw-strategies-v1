// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { BytesLib } from "@uniswap/v3-periphery/contracts/libraries/BytesLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUniswapV3Pool } from "@jigsaw/lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { FixedPoint96 } from "@jigsaw/lib/v3-core/contracts/libraries/FixedPoint96.sol";
import { FullMath } from "@jigsaw/lib/v3-core/contracts/libraries/FullMath.sol";
import { GenericUniswapV3Oracle } from "@jigsaw/src/oracles/uniswap/GenericUniswapV3Oracle.sol";

import { ISwapRouter } from "@jigsaw/lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IHoldingManager } from "@jigsaw/src/interfaces/core/IHoldingManager.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";
import { ISwapManager } from "@jigsaw/src/interfaces/core/ISwapManager.sol";

import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";
import { ISdeUsdMin } from "./interfaces/ISdeUsdMin.sol";

import { StrategyBaseUpgradeableV2 } from "../StrategyBaseUpgradeableV2.sol";

import { IFeeManager } from "../extensions/interfaces/IFeeManager.sol";
import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";

/**
 * @title ElixirStrategy
 * @dev Strategy used for deUSD minting and staking mechanisms.
 * @notice Implements deposit, withdrawal, and reward management for Elixir's deUSD strategy.
 * @author Hovooo (@hovooo)
 */
contract ElixirStrategy is IStrategy, StrategyBaseUpgradeableV2 {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;
    using BytesLib for bytes;

    // -- Enums --

    /**
     * @notice The direction of the swap.
     */
    enum SwapDirection {
        FromTokenIn,
        ToTokenIn
    }

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     */
    struct InitializerParams {
        address owner; // The address of the initial owner of the Strategy contract
        address manager; // The address of the manager contract
        address stakerFactory; // The address of the StakerLightFactory contract
        address jigsawRewardToken; // The address of the Jigsaw reward token associated with the strategy
        uint256 jigsawRewardDuration; // The address of the initial Jigsaw reward distribution duration for the strategy
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of Elixir's receipt token
        address deUSD; // The Elixir's deUSD stablecoin.
        address uniswapRouter; // The address of the UniswapV3 Router
        address oracle; // The address of the UniswapV3 Oracle
        address[] initialPools; // The address array of the UniswapV3 pools
        address feeManager; // The address of the feeManager contract
    }

    // -- Errors --

    /**
     * @notice Thrown when an unsupported operation is attempted.
     */
    error OperationNotSupported();

    /**
     * @notice Thrown when the swap path length is invalid.
     */
    error InvalidSwapPathLength();

    /**
     * @notice Thrown when the first token in the swap path is invalid.
     */
    error InvalidFirstTokenInPath();

    /**
     * @notice Thrown when the last token in the swap path is invalid.
     */
    error InvalidLastTokenInPath();

    /**
     * @notice Thrown when the minimum output amount is invalid.
     */
    error InvalidAmountOutMin();

    // -- Events --

    /**
     * @notice Emitted when the slippage percentage is updated.
     * @param oldValue The previous slippage percentage value.
     * @param newValue The new slippage percentage value.
     */
    event SlippagePercentageSet(uint256 oldValue, uint256 newValue);

    /**
     * @notice Emitted when exact input swap is executed on UniswapV3 Pool.
     * @param holding The holding address associated with the user.
     * @param path The optimal path for the multi-hop swap.
     * @param amountIn The amount of the input token used for the swap.
     * @param amountOut The amount of the output token received after the swap.
     */
    event ExactInputSwap(address indexed holding, bytes path, uint256 amountIn, uint256 amountOut);

    // -- State variables --

    /**
     * @notice The tokenIn address for the strategy.
     */
    address public override tokenIn;

    /**
     * @notice The tokenOut address (deUSD) for the strategy.
     */
    address public override tokenOut;

    /**
     * @notice The reward token offered to users.
     */
    address public override rewardToken;

    /**
     * @notice The receipt token associated with this strategy.
     */
    IReceiptToken public override receiptToken;

    /**
     * @notice The Elixir's Stablecoin deUSD.
     */
    address public deUSD;

    /**
     * @notice The Uniswap Router.
     */
    address public uniswapRouter;

    /**
     * @notice The Jigsaw Rewards Controller contract.
     */
    IStakerLight public jigsawStaker;

    /**
     * @notice The sdeUSD Controller contract.
     */
    ISdeUsdMin public sdeUSD;

    /**
     * @notice The GenericUniswapV3Oracle contract.
     */
    GenericUniswapV3Oracle public oracle;

    /**
     * @notice The number of decimals of the strategy's shares.
     */
    uint256 public override sharesDecimals;

    /**
     * @notice Returns the maximum allowed slippage percentage.
     * @dev Uses 2 decimal precision, where 1% is represented as 100.
     */
    uint256 public allowedSlippagePercentage;

    /**
     * @notice The slippage factor.
     */
    uint256 public constant SLIPPAGE_PRECISION = 1e4;

    /**
     * @notice The length of the bytes encoded address.
     */
    uint256 private constant ADDR_SIZE = 20;

    /**
     * @notice A mapping that stores participant details by address.
     */
    mapping(address recipient => IStrategy.RecipientInfo info) public override recipients;

    // -- Constructor --

    /**
     * @notice Disables initializers to prevent misuse.
     */
    constructor() {
        _disableInitializers();
    }

    // -- Initialization --

    /**
     * @notice Initializes the Elixir Strategy contract with necessary parameters.
     *
     * @dev Configures core components such as manager, tokens, pools, and reward systems needed for the strategy to
     * operate.
     *
     * @dev This function is only callable once due to the `initializer` modifier.
     *
     * @notice Ensures that critical addresses are non-zero to prevent misconfiguration:
     * - `_params.manager` must be valid (`"3065"` error code if invalid).
     * - `_params.tokenIn` and `_params.tokenOut` must be valid (`"3000"` error code if invalid).
     * - `_params.feeManager` must be valid (`"3000"` error code if invalid).
     *
     * @param _params Struct containing all initialization parameters.
     */
    function initialize(
        InitializerParams memory _params
    ) public initializer {
        require(_params.manager != address(0), "3065");
        require(_params.jigsawRewardToken != address(0), "3000");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");
        require(_params.deUSD != address(0), "3036");
        require(_params.uniswapRouter != address(0), "3000");
        require(_params.oracle != address(0), "3000");
        require(_params.initialPools.length != 0, "3000");
        require(_params.feeManager != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        oracle = new GenericUniswapV3Oracle({
            _initialOwner: _params.owner,
            _underlying: _params.tokenIn,
            _quoteToken: _params.deUSD,
            _quoteTokenOracle: _params.oracle,
            _uniswapV3Pools: _params.initialPools
        });

        manager = IManager(_params.manager);
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();
        rewardToken = address(0);
        deUSD = _params.deUSD;
        sdeUSD = ISdeUsdMin(_params.tokenOut);
        uniswapRouter = _params.uniswapRouter;
        feeManager = IFeeManager(_params.feeManager);

        // Set default allowed slippage percentage to 5%
        _setSlippagePercentage({ _newVal: 500 });

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: manager.receiptTokenFactory(),
                _receiptTokenName: "Elixir Receipt Token",
                _receiptTokenSymbol: "ElRT"
            })
        );

        jigsawStaker = IStakerLight(
            IStakerLightFactory(_params.stakerFactory).createStakerLight({
                _initialOwner: _params.owner,
                _holdingManager: manager.holdingManager(),
                _rewardToken: _params.jigsawRewardToken,
                _strategy: address(this),
                _rewardsDuration: _params.jigsawRewardDuration
            })
        );
    }

    // -- User-specific Methods --

    /**
     * @notice Deposits funds into the strategy.
     *
     * @param _asset The token to be invested.
     * @param _amount The amount of the token to be invested.
     * @param _recipient The address on behalf of which the funds are deposited.
     * @param _data Encoded data used for UniswapV3 swap.
     *
     * @return The amount of receipt tokens obtained.
     * @return The amount of the 'tokenIn()' token.
     */
    function deposit(
        address _asset,
        uint256 _amount,
        address _recipient,
        bytes calldata _data
    ) external override nonReentrant onlyValidAmount(_amount) onlyStrategyManager returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");

        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });
        uint256 deUsdBalanceBefore = IERC20(deUSD).balanceOf(address(this));

        // Swap USDT to deUSD on Uniswap
        _swapExactInputMultihop({
            _tokenIn: _asset,
            _amountIn: _amount,
            _recipient: address(this),
            _swapData: _data,
            _swapDirection: SwapDirection.FromTokenIn
        });

        uint256 deUSDAmount = IERC20(deUSD).balanceOf(address(this)) - deUsdBalanceBefore;
        uint256 balanceBefore = sdeUSD.balanceOf(_recipient);
        IERC20(deUSD).forceApprove({ spender: tokenOut, value: deUSDAmount });

        // Stake deUSD to receive sdeUSD (Elixir's staked deUSD receipt token)
        sdeUSD.deposit({ assets: deUSDAmount, receiver: _recipient });

        uint256 shares = sdeUSD.balanceOf(_recipient) - balanceBefore;

        recipients[_recipient].investedAmount += _amount;
        recipients[_recipient].totalShares += shares;

        _mint({ _receiptToken: receiptToken, _recipient: _recipient, _amount: shares, _tokenDecimals: sharesDecimals });

        jigsawStaker.deposit({ _user: _recipient, _amount: shares });

        emit Deposit({
            asset: _asset,
            tokenIn: tokenIn,
            assetAmount: _amount,
            tokenInAmount: _amount,
            shares: shares,
            recipient: _recipient
        });

        return (shares, _amount);
    }

    /**
     * @notice Withdraws deposited funds from the strategy.
     *
     * @dev Some strategies will only allow the tokenIn to be withdrawn.
     * @dev 'assetAmount' will be equal to 'tokenInAmount' if '_asset' is the same as the strategy's 'tokenIn()'.
     *
     * @param _shares The amount of shares to withdraw.
     * @param _recipient The address on behalf of which the funds are withdrawn.
     * @param _asset The token to be withdrawn.
     * @param _data The data containing the token output .
     *
     * @return withdrawnAmount The actual amount of asset withdrawn from the strategy.
     * @return initialInvestment The amount of initial investment.
     * @return yield The amount of yield generated by the user beyond their initial investment.
     * @return fee The amount of fee charged by the strategy.
     */
    function withdraw(
        uint256 _shares,
        address _recipient,
        address _asset,
        bytes calldata _data
    ) external override nonReentrant onlyStrategyManager returns (uint256, uint256, int256, uint256) {
        require(_asset == tokenIn, "3001");

        WithdrawParams memory params = WithdrawParams({
            shares: _shares,
            totalShares: recipients[_recipient].totalShares,
            shareRatio: 0,
            shareDecimals: sharesDecimals,
            investment: 0,
            assetsToWithdraw: 0,
            balanceBefore: 0,
            withdrawnAmount: 0,
            yield: 0,
            fee: 0
        });

        params.shareRatio = OperationsLib.getRatio({
            numerator: params.shares,
            denominator: params.totalShares,
            precision: params.shareDecimals,
            rounding: OperationsLib.Rounding.Floor
        });

        _burn({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _shares: params.shares,
            _totalShares: params.totalShares,
            _tokenDecimals: params.shareDecimals
        });

        params.investment = (recipients[_recipient].investedAmount * params.shareRatio) / 10 ** params.shareDecimals;
        uint256 deUsdBalanceBefore = IERC20(deUSD).balanceOf(address(this));

        _genericCall({
            _holding: _recipient,
            _contract: tokenOut,
            _call: abi.encodeCall(ISdeUsdMin.unstake, (address(this)))
        });

        uint256 deUsdAmount = IERC20(deUSD).balanceOf(address(this)) - deUsdBalanceBefore;

        // Swap deUSD to USDT on Uniswap
        _swapExactInputMultihop({
            _tokenIn: deUSD,
            _amountIn: deUsdAmount,
            _recipient: _recipient,
            _swapData: _data,
            _swapDirection: SwapDirection.ToTokenIn
        });

        // Take protocol's fee from generated yield if any.
        params.withdrawnAmount = IERC20(tokenIn).balanceOf(_recipient) - params.balanceBefore;
        params.yield = params.withdrawnAmount.toInt256() - params.investment.toInt256();

        // Take protocol's fee from generated yield if any.
        if (params.yield > 0) {
            params.fee = _takePerformanceFee({ _token: tokenIn, _recipient: _recipient, _yield: uint256(params.yield) });
            if (params.fee > 0) {
                params.withdrawnAmount -= params.fee;
                params.yield -= params.fee.toInt256();
            }
        }

        recipients[_recipient].totalShares -= _shares;
        recipients[_recipient].investedAmount = params.investment > recipients[_recipient].investedAmount
            ? 0
            : recipients[_recipient].investedAmount - params.investment;

        emit Withdraw({
            asset: _asset,
            recipient: _recipient,
            shares: params.shares,
            withdrawnAmount: params.withdrawnAmount,
            initialInvestment: params.investment,
            yield: params.yield
        });

        // Register `_recipient`'s withdrawal operation to stop generating jigsaw rewards.
        jigsawStaker.withdraw({ _user: _recipient, _amount: _shares });

        return (params.withdrawnAmount, params.investment, params.yield, params.fee);
    }

    /**
     * @notice Claims rewards from Elixir.
     * @return The amounts of rewards claimed.
     * @return The addresses of the reward tokens.
     */
    function claimRewards(
        address,
        bytes calldata
    ) external pure override returns (uint256[] memory, address[] memory) {
        revert OperationNotSupported();
    }

    /**
     * @notice Starts a cooldown to claim the converted underlying asset.
     * @param _recipient The address on behalf of which the funds are withdrawn.
     * @param _shares The amount of shares to withdraw.
     */
    function cooldown(address _recipient, uint256 _shares) external nonReentrant {
        require(
            msg.sender == owner() || msg.sender == IHoldingManager(manager.holdingManager()).holdingUser(_recipient),
            "1001"
        );

        _genericCall({
            _holding: _recipient,
            _contract: tokenOut,
            _call: abi.encodeCall(ISdeUsdMin.cooldownShares, _shares)
        });
    }

    // -- Administration --

    /**
     * @notice Sets a new slippage percentage for the strategy.
     * @param _newVal The new slippage percentage value (must be <= SLIPPAGE_PRECISION).
     */
    function setSlippagePercentage(
        uint256 _newVal
    ) external onlyOwner {
        _setSlippagePercentage({ _newVal: _newVal });
    }

    // -- Getters --

    /**
     * @notice Returns the address of the receipt token.
     */
    function getReceiptTokenAddress() external view override returns (address) {
        return address(receiptToken);
    }

    /**
     * @notice Calculates the minimum acceptable amount
     * @param _amount The amount of shares.
     * @return The minimum acceptable asset tokens received for specified shares amount.
     */
    function getAllowedAmountOutMin(uint256 _amount, SwapDirection _swapDirection) public view returns (uint256) {
        // Get tokenIn rate to get  minimum acceptable amount out
        (, uint256 rate) = oracle.peek(bytes(""));
        uint256 expectedTokenOut = _swapDirection == SwapDirection.FromTokenIn
            ? _amount.mulDiv(1e18, rate, Math.Rounding.Ceil)
            : _amount.mulDiv(rate, 1e18, Math.Rounding.Ceil);

        // Calculate min tokenOut amount with max allowed slippage
        return _applySlippage(expectedTokenOut);
    }

    // -- Utilities --

    /**
     * @notice Swaps a fixed amount of `_tokenIn` for a maximum possible amount of `tokenOut` via `_swapPath`.
     *
     * @notice Effects:
     * - Approves and transfers `tokenIn` from the `_userHolding`.
     * - Approves UniswapV3 Router to transfer `tokenIn` from address(this) to perform the `exactInput` swap.
     * - Executes the `exactInput` swap
     * - Handles any excess tokens.
     *
     * @param _tokenIn The address of the inbound asset.
     * @param _amountIn The desired amount of `tokenIn`.
     * @param _recipient The address of recipient.
     * @param _swapData Encoded data used for UniswapV3 swap.
     * @param _swapDirection The direction of the swap.
     *
     * @return amountOut The amount of `_tokenIn` spent to receive the desired `amountOut` of `tokenOut`.
     */
    function _swapExactInputMultihop(
        address _tokenIn,
        uint256 _amountIn,
        address _recipient,
        bytes calldata _swapData,
        SwapDirection _swapDirection
    ) private returns (uint256 amountOut) {
        // Decode the data to get the swap path
        (uint256 amountOutMinimum, uint256 deadline, bytes memory swapPath) =
            abi.decode(_swapData, (uint256, uint256, bytes));

        // Validate swap path length
        // Minimum path length is 43 bytes (length of smallest encoded pool key = address[20] + fee[3] + address[20])
        if (swapPath.length < 43) revert InvalidSwapPathLength();

        // Validate token path integrity for FromTokenIn direction:
        // - First token must be tokenIn
        // - Last token must be `deUSD` that's later used for staking
        if (_swapDirection == SwapDirection.FromTokenIn) {
            if (swapPath.toAddress(0) != tokenIn) revert InvalidFirstTokenInPath();
            if (swapPath.toAddress(swapPath.length - ADDR_SIZE) != deUSD) revert InvalidLastTokenInPath();
        }

        // Validate token path integrity for ToTokenIn direction:
        // - First token must be tokenOut
        // - Last token must be `deUSD` that's later used for unstaking
        if (_swapDirection == SwapDirection.ToTokenIn) {
            if (swapPath.toAddress(0) != deUSD) revert InvalidFirstTokenInPath();
            if (swapPath.toAddress(swapPath.length - ADDR_SIZE) != tokenIn) revert InvalidLastTokenInPath();
        }

        // Validate amountOutMin is within allowed slippage
        if (amountOutMinimum < getAllowedAmountOutMin(_amountIn, _swapDirection)) revert InvalidAmountOutMin();

        // Approve the router to spend `_tokenIn`.
        IERC20(_tokenIn).forceApprove({ spender: uniswapRouter, value: _amountIn });

        // A path is a  encoded as (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut).
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: swapPath,
            recipient: _recipient,
            deadline: deadline,
            amountIn: _amountIn,
            amountOutMinimum: amountOutMinimum
        });

        // Execute the swap, returning the amountIn actually spent.
        try ISwapRouter(uniswapRouter).exactInput(params) returns (uint256 _amountOut) {
            amountOut = _amountOut;
        } catch {
            revert("3084");
        }

        // Emit event indicating successful exact output swap.
        emit ExactInputSwap({ holding: _recipient, path: swapPath, amountIn: _amountIn, amountOut: amountOut });
    }

    /**
     * @notice Applies slippage tolerance to a given value.
     * @dev Reduces the input value by the configured slippage percentage.
     * @param _value The value to apply slippage to.
     * @return The value after slippage has been applied (reduced).
     */
    function _applySlippage(
        uint256 _value
    ) private view returns (uint256) {
        return _value - ((_value * allowedSlippagePercentage) / SLIPPAGE_PRECISION);
    }

    /**
     * @notice Sets a new slippage percentage for the strategy.
     * @dev Emits a SlippagePercentageSet event.
     * @param _newVal The new slippage percentage value (must be <= SLIPPAGE_PRECISION).
     */
    function _setSlippagePercentage(
        uint256 _newVal
    ) private {
        require(_newVal <= SLIPPAGE_PRECISION, "3002");
        emit SlippagePercentageSet({ oldValue: allowedSlippagePercentage, newValue: _newVal });
        allowedSlippagePercentage = _newVal;
    }
}
