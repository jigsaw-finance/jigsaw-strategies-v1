// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "@pendle/interfaces/IPAllActionV3.sol";
import { IPMarket, IPYieldToken, IStandardizedYield } from "@pendle/interfaces/IPMarket.sol";

import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManagerContainer } from "@jigsaw/src/interfaces/core/IManagerContainer.sol";
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

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     * @param owner The address of the initial owner of the Strategy contract
     * @param managerContainer The address of the contract that contains the manager contract
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
        address managerContainer;
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

    // -- Errors --

    error InvalidTokenIn();
    error InvalidTokenOut();
    error PendleSwapNotEmpty();
    error SwapDataNotEmpty();

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
     * @notice The Pendle's CreditEnforcer contract.
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
     * - `_params.managerContainer` must be valid (`"3065"` error code if invalid).
     * - `_params.pendleRouter` must be valid (`"3036"` error code if invalid).
     * - `_params.pendleMarket` must be valid (`"3036"` error code if invalid).
     * - `_params.tokenIn` and `_params.tokenOut` must be valid (`"3000"` error code if invalid).
     * - `_params.rewardToken` must be valid (`"3000"` error code if invalid).
     */
    function initialize(
        InitializerParams memory _params
    ) public initializer {
        require(_params.managerContainer != address(0), "3065");
        require(_params.pendleRouter != address(0), "3036");
        require(_params.pendleMarket != address(0), "3036");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");
        require(_params.rewardToken != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        managerContainer = IManagerContainer(_params.managerContainer);
        pendleRouter = IPAllActionV3(_params.pendleRouter);
        pendleMarket = _params.pendleMarket;
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        rewardToken = _params.rewardToken;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();
        EMPTY_SWAP_DATA_HASH = 0x95e00231cb51f973e9db40dd7466e602a0dcf1466ba8363089a90b5cb5416a27;

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: _getManager().receiptTokenFactory(),
                _receiptTokenName: "Pendle Receipt Token",
                _receiptTokenSymbol: "PeRT"
            })
        );

        jigsawStaker = IStakerLight(
            IStakerLightFactory(_params.stakerFactory).createStakerLight({
                _initialOwner: _params.owner,
                _holdingManager: _getManager().holdingManager(),
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

        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_recipient);
        OperationsLib.safeApprove({ token: _asset, to: address(pendleRouter), value: _amount });

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
        address feeAddr = _getManager().feeAddress();

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

    // -- Getters --

    /**
     * @notice Returns the address of the receipt token.
     */
    function getReceiptTokenAddress() external view override returns (address) {
        return address(receiptToken);
    }
}
