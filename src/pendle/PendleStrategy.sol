// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "@pendle/interfaces/IPAllActionV3.sol";
import { IPMarket, IPYieldToken, IStandardizedYield } from "@pendle/interfaces/IPMarket.sol";
import { PendleLpOracleLib } from "@pendle/oracles/PendleLpOracleLib.sol";

import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";

import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";

import { StrategyBaseUpgradeable } from "../StrategyBaseUpgradeable.sol";

/**
 * @title PendleStrategy
 * @dev Strategy used for investments into Pendle strategy.
 * @author Hovooo (@hovooo)
 */
contract PendleStrategy is IStrategy, StrategyBaseUpgradeable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;
    using PendleLpOracleLib for IPMarket;

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     * @param owner The address of the initial owner of the Strategy contract
     * @param manager The address of the Manager contract
     * @param pendleRouter The address of the Pendle's Router contract
     * @param pendleMarket The address of the Pendle's Market contract used for strategy
     * @param stakerFactory The address of the StakerLightFactory contract
     * @param jigsawRewardToken The address of the Jigsaw reward token associated with the strategy
     * @param jigsawRewardDuration The address of the initial Jigsaw reward distribution duration for the strategy
     * @param tokenIn The address of the LP token
     * @param tokenOut The address of the Pendle receipt token
     * @param rewardToken The address of the Pendle primary reward token
     */
    struct InitializerParams {
        address owner;
        address manager;
        address pendleRouter;
        address pendleMarket;
        address stakerFactory;
        address jigsawRewardToken;
        uint256 jigsawRewardDuration;
        address tokenIn;
        address tokenOut;
        address rewardToken;
    }

    /**
     * @notice Struct containing parameters for a deposit operation.
     * @param minLpOut The minimum amount of LP tokens to receive
     * @param guessPtReceivedFromSy The estimated amount of PT received from the strategy
     * @param input The input parameters for the pendleRouter addLiquiditySingleToken function
     * @param limit The limit parameters for the pendleRouter addLiquiditySingleToken function
     */
    struct DepositParams {
        uint256 minLpOut;
        ApproxParams guessPtReceivedFromSy;
        TokenInput input;
        LimitOrderData limit;
    }

    // -- Events --

    /**
     * @notice Emitted when the slippage percentage is updated.
     * @param oldValue The previous slippage percentage value.
     * @param newValue The new slippage percentage value.
     */
    event SlippagePercentageSet(uint256 oldValue, uint256 newValue);

    // -- Errors --

    error InvalidTokenIn();
    error InvalidTokenOut();
    error PendleSwapNotEmpty();
    error SwapDataNotEmpty();

    /**
     * @notice The specified minimum LP tokens out is less than the minimum allowed LP tokens out.
     * @param minLpOut The specified minimum LP tokens out provided.
     * @param minAllowedLpOut The minimum allowed LP tokens out.
     */
    error InvalidMinLpOut(uint256 minLpOut, uint256 minAllowedLpOut);

    /**
     * @notice The specified minimum token out is less than the minimum allowed token out.
     * @param minTokenOut The specified minimum token out provided.
     * @param minAllowedTokenOut The minimum allowed token out.
     */
    error InvalidMinTokenOut(uint256 minTokenOut, uint256 minAllowedTokenOut);

    // -- State variables --

    /**
     * @notice The tokenIn address for the strategy.
     */
    address public override tokenIn;

    /**
     * @notice The tokenOut address for the strategy.
     */
    address public override tokenOut;

    /**
     * @notice The Pendle's reward token offered to users.
     */
    address public override rewardToken;

    /**
     * @notice The receipt token associated with this strategy.
     */
    IReceiptToken public override receiptToken;

    /**
     * @notice The Pendle's Router contract.
     */
    IPAllActionV3 public pendleRouter;

    /**
     * @notice The Pendle's PegStabilityModule contract.
     */
    address public pendleMarket;

    /**
     * @notice The Jigsaw Rewards Controller contract.
     */
    IStakerLight public jigsawStaker;

    /**
     * @notice The number of decimals of the strategy's shares.
     */
    uint256 public override sharesDecimals;

    /**
     * @notice The empty limit order data.
     */
    LimitOrderData public EMPTY_LIMIT_ORDER_DATA;

    /**
     * @notice The keccak256 hash of the empty limit order data.
     */
    bytes32 public EMPTY_SWAP_DATA_HASH;

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
     * @notice The precision used for the Pendle LP price.
     */
    uint256 public constant PENDLE_LP_PRICE_PRECISION = 1e18;

    /**
     * @notice A mapping that stores participant details by address.
     */
    mapping(address recipient => IStrategy.RecipientInfo info) public override recipients;

    // -- Constructor --

    constructor() {
        _disableInitializers();
    }

    // -- Initialization --

    /**
     * @notice Initializes the Pendle Strategy contract with necessary parameters.
     *
     * @dev Configures core components such as manager, tokens, pools, and reward systems
     * needed for the strategy to operate.
     *
     * @dev This function is only callable once due to the `initializer` modifier.
     *
     * @notice Ensures that critical addresses are non-zero to prevent misconfiguration:
     * - `_params.manager` must be valid (`"3065"` error code if invalid).
     * - `_params.pendleRouter` must be valid (`"3036"` error code if invalid).
     * - `_params.pendleMarket` must be valid (`"3036"` error code if invalid).
     * - `_params.tokenIn` and `_params.tokenOut` must be valid (`"3000"` error code if invalid).
     * - `_params.rewardToken` must be valid (`"3000"` error code if invalid).
     *
     * @param _params Struct containing all initialization parameters.
     */
    function initialize(
        InitializerParams memory _params
    ) public initializer {
        require(_params.manager != address(0), "3065");
        require(_params.pendleRouter != address(0), "3036");
        require(_params.pendleMarket != address(0), "3036");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");
        require(_params.rewardToken != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        manager = IManager(_params.manager);
        pendleRouter = IPAllActionV3(_params.pendleRouter);
        pendleMarket = _params.pendleMarket;
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        rewardToken = _params.rewardToken;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();
        EMPTY_SWAP_DATA_HASH = 0x95e00231cb51f973e9db40dd7466e602a0dcf1466ba8363089a90b5cb5416a27;

        // Set default allowed slippage percentage to 5%
        _setSlippagePercentage({ _newVal: 500 });

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: manager.receiptTokenFactory(),
                _receiptTokenName: "Pendle Receipt Token",
                _receiptTokenSymbol: "PeRT"
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
     * @param _data The data containing the deposit parameters.
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

        DepositParams memory params;
        (params.minLpOut, params.guessPtReceivedFromSy, params.input) =
            abi.decode(_data, (uint256, ApproxParams, TokenInput));

        require(params.input.tokenIn == tokenIn, "3001");
        require(params.input.netTokenIn == _amount, "2001");

        if (params.input.pendleSwap != address(0)) revert PendleSwapNotEmpty();
        if (params.input.tokenMintSy != tokenIn) revert InvalidTokenIn();
        if (keccak256(abi.encode(params.input.swapData)) != EMPTY_SWAP_DATA_HASH) revert SwapDataNotEmpty();
        if (params.minLpOut < getMinAllowedLpOut({ _amount: _amount })) {
            revert InvalidMinLpOut({
                minLpOut: params.minLpOut,
                minAllowedLpOut: getMinAllowedLpOut({ _amount: _amount })
            });
        }

        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_recipient);
        IERC20(_asset).forceApprove({ spender: address(pendleRouter), value: _amount });

        pendleRouter.addLiquiditySingleToken({
            receiver: _recipient,
            market: pendleMarket,
            minLpOut: params.minLpOut,
            guessPtReceivedFromSy: params.guessPtReceivedFromSy,
            input: params.input,
            limit: EMPTY_LIMIT_ORDER_DATA
        });

        uint256 shares = IERC20(tokenOut).balanceOf(_recipient) - balanceBefore;

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
        require(_shares <= IERC20(tokenOut).balanceOf(_recipient), "2002");

        WithdrawParams memory params = WithdrawParams({
            shares: _shares,
            totalShares: recipients[_recipient].totalShares,
            shareRatio: 0,
            shareDecimals: sharesDecimals,
            investment: 0,
            assetsToWithdraw: 0, // not used in Pendle strategy
            balanceBefore: 0,
            withdrawnAmount: 0,
            yield: 0,
            fee: 0
        });

        // Decode pendle's output params used for removeLiquiditySingleToken.
        TokenOutput memory output = abi.decode(_data, (TokenOutput));

        if (output.pendleSwap != address(0)) revert PendleSwapNotEmpty();
        if (output.tokenOut != tokenIn || output.tokenRedeemSy != tokenIn) revert InvalidTokenOut();
        if (keccak256(abi.encode(output.swapData)) != EMPTY_SWAP_DATA_HASH) revert SwapDataNotEmpty();

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

        // To accurately compute the protocol's fees from the yield generated by the strategy, we first need to
        // determine the percentage of the initial investment being withdrawn. This allows us to assess whether any
        // yield has been generated beyond the initial investment.
        params.investment = (recipients[_recipient].investedAmount * params.shareRatio) / (10 ** params.shareDecimals);
        params.balanceBefore = IERC20(tokenIn).balanceOf(_recipient);

        uint256 minAllowedTokenOut = getMinAllowedTokenOut({ _amount: _shares });
        if (output.minTokenOut < minAllowedTokenOut) {
            revert InvalidMinTokenOut({ minTokenOut: output.minTokenOut, minAllowedTokenOut: minAllowedTokenOut });
        }

        IHolding(_recipient).approve({
            _tokenAddress: tokenOut,
            _destination: address(pendleRouter),
            _amount: params.shares
        });

        _genericCall({
            _holding: _recipient,
            _contract: address(pendleRouter),
            _call: abi.encodeCall(
                IPActionAddRemoveLiqV3.removeLiquiditySingleToken,
                (_recipient, pendleMarket, params.shares, output, EMPTY_LIMIT_ORDER_DATA)
            )
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

        recipients[_recipient].totalShares -= params.shares;
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
        jigsawStaker.withdraw({ _user: _recipient, _amount: params.shares });

        return (params.withdrawnAmount, params.investment, params.yield, params.fee);
    }

    /**
     * @notice Claims rewards from the Pendle Pool.
     * @return claimedAmounts The amounts of rewards claimed.
     * @return rewardsList The addresses of the reward tokens.
     */
    function claimRewards(
        address _recipient,
        bytes calldata
    )
        external
        override
        nonReentrant
        onlyStrategyManager
        returns (uint256[] memory claimedAmounts, address[] memory rewardsList)
    {
        (, bytes memory returnData) = _genericCall({
            _holding: _recipient,
            _contract: pendleMarket,
            _call: abi.encodeCall(IPMarket.redeemRewards, _recipient)
        });

        // Get Pendle data.
        rewardsList = IPMarket(pendleMarket).getRewardTokens();
        claimedAmounts = abi.decode(returnData, (uint256[]));

        // Get fee data.
        (uint256 performanceFee,,) = _getStrategyManager().strategyInfo(address(this));
        address feeAddr = manager.feeAddress();

        for (uint256 i = 0; i < claimedAmounts.length; i++) {
            // Take protocol fee for all non zero rewards.
            if (claimedAmounts[i] != 0) {
                uint256 fee = OperationsLib.getFeeAbsolute(claimedAmounts[i], performanceFee);
                if (fee > 0) {
                    claimedAmounts[i] -= fee;
                    emit FeeTaken(rewardsList[i], feeAddr, fee);
                    IHolding(_recipient).transfer({ _token: rewardsList[i], _to: feeAddr, _amount: fee });
                }
            }
        }

        emit Rewards({ recipient: _recipient, rewards: claimedAmounts, rewardTokens: rewardsList });
        return (claimedAmounts, rewardsList);
    }

    // -- Administration --

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
     * @notice Calculates the minimum acceptable LP tokens received based on input amount and slippage tolerance.
     * @dev Uses median of different timeframe rates to get a more stable price.
     * @param _amount The amount of input tokens.
     * @return The minimum acceptable LP tokens for the specified input amount.
     */
    function getMinAllowedLpOut(
        uint256 _amount
    ) public view returns (uint256) {
        // Calculate expected LP tokens based on Pendle's LpToAssetRate
        uint256 expectedLpOut = _amount.mulDiv(PENDLE_LP_PRICE_PRECISION, _getMedianLpToAssetRate(), Math.Rounding.Ceil);
        // Calculate minLp amount with max allowed slippage
        return _applySlippage(expectedLpOut);
    }

    /**
     * @notice Calculates the minimum acceptable asset tokens received based on provided shares and slippage tolerance.
     * @dev Uses median of different timeframe rates to get a more stable price.
     * @param _amount The amount of shares.
     * @return The minimum acceptable asset tokens received for specified shares amount.
     */
    function getMinAllowedTokenOut(
        uint256 _amount
    ) public view returns (uint256) {
        // Calculate expected LP tokens based on Pendle's LpToAssetRate
        uint256 expectedTokenOut =
            _amount.mulDiv(_getMedianLpToAssetRate(), PENDLE_LP_PRICE_PRECISION, Math.Rounding.Ceil);
        // Calculate min tokenOut amount with max allowed slippage
        return _applySlippage(expectedTokenOut);
    }

    // -- Utility Functions --

    /**
     * @notice Gets the median LP to asset rate from Pendle market across different timeframes.
     * @dev Uses 30 minutes, 1 hour, and 2 hour timeframes to calculate a stable median rate.
     * @return The median LP to asset rate from the Pendle market.
     */
    function _getMedianLpToAssetRate() internal view returns (uint256) {
        return _getMedian(
            IPMarket(pendleMarket).getLpToAssetRate(30 minutes),
            IPMarket(pendleMarket).getLpToAssetRate(1 hours),
            IPMarket(pendleMarket).getLpToAssetRate(2 hours)
        );
    }

    /**
     * @notice Computes a median value from three numbers.
     */
    function _getMedian(uint256 _a, uint256 _b, uint256 _c) internal pure returns (uint256) {
        if ((_a >= _b && _a <= _c) || (_a >= _c && _a <= _b)) return _a;
        if ((_b >= _a && _b <= _c) || (_b >= _c && _b <= _a)) return _b;
        return _c;
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
