// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     */
    struct InitializerParams {
        address owner; // The address of the initial owner of the Strategy contract
        address managerContainer; // The address of the contract that contains the manager contract
        address pendleRouter; // The address of the Pendle's Router contract
        address pendleMarket; // The Pendle's Router contract.
        address stakerFactory; // The address of the StakerLightFactory contract
        address jigsawRewardToken; // The address of the Jigsaw reward token associated with the strategy
        uint256 jigsawRewardDuration; // The address of the initial Jigsaw reward distribution duration for the strategy
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of the Pendle receipt token
        address rewardToken; // The address of the Pendle primary reward token
    }

    /**
     * @notice Struct containing parameters for a deposit operation.
     */
    struct DepositParams {
        uint256 minLpOut;
        ApproxParams guessPtReceivedFromSy;
        TokenInput input;
        LimitOrderData limit;
    }

    /**
     * @notice Struct containing parameters for a withdrawal operation.
     */
    struct WithdrawParams {
        uint256 shareRatio; // The share ratio representing the proportion of the total investment owned by the user.
        uint256 investment; // The amount of funds invested by the user.
        uint256 balanceBefore; // The user's balance in the system before the withdrawal transaction.
        uint256 balanceAfter; // The user's balance in the system after the withdrawal transaction is completed.
        uint256 balanceDiff; // The difference between balanceAfter and balanceBefore.
        uint256 performanceFee; // Protocol's performanceFee applied to extra generated yield.
        TokenOutput output; // Pendle's output param.
        LimitOrderData limit; // Pendle's limit param.
    }

    // -- Errors --

    error OperationNotSupported();

    // -- Events --

    /**
     * @notice Emitted when a performance fee is taken.
     * @param token The token from which the fee is taken.
     * @param feeAddress The address that receives the fee.
     * @param amount The amount of the fee.
     */
    event FeeTaken(address indexed token, address indexed feeAddress, uint256 amount);

    // -- State variables --

    /**
     * @notice The tokenIn address for the strategy.
     */
    address public override tokenIn;

    /**
     * @notice The tokenOut address (rUSD) for the strategy.
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
     * @notice A mapping that stores participant details by address.
     */
    mapping(address => IStrategy.RecipientInfo) public override recipients;

    // -- Constructor --

    constructor() {
        _disableInitializers();
    }

    // -- Initialization --

    /**
     * @notice Initializer for the Pendle Strategy.
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

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
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
        (params.minLpOut, params.guessPtReceivedFromSy, params.input, params.limit) =
            abi.decode(_data, (uint256, ApproxParams, TokenInput, LimitOrderData));

        require(params.input.tokenIn == tokenIn, "3001");
        require(params.input.netTokenIn == _amount, "2001");

        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_recipient);
        OperationsLib.safeApprove({ token: _asset, to: address(pendleRouter), value: _amount });

        pendleRouter.addLiquiditySingleToken({
            receiver: _recipient,
            market: pendleMarket,
            minLpOut: params.minLpOut,
            guessPtReceivedFromSy: params.guessPtReceivedFromSy,
            input: params.input,
            limit: params.limit
        });

        uint256 shares = IERC20(tokenOut).balanceOf(_recipient) - balanceBefore;

        recipients[_recipient].investedAmount += _amount;
        recipients[_recipient].totalShares += shares;

        _mint({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _amount: shares,
            _tokenDecimals: IERC20Metadata(tokenOut).decimals()
        });

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
     *
     * @return The amount of the asset obtained from the operation.
     * @return The amount of the 'tokenIn()' token.
     */
    function withdraw(
        uint256 _shares,
        address _recipient,
        address _asset,
        bytes calldata _data
    ) external override nonReentrant onlyStrategyManager returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");
        require(_shares <= IERC20(tokenOut).balanceOf(_recipient), "2002");

        WithdrawParams memory params;
        (params.output, params.limit) = abi.decode(_data, (TokenOutput, LimitOrderData));

        params.shareRatio = OperationsLib.getRatio({
            numerator: _shares,
            denominator: recipients[_recipient].totalShares,
            precision: IERC20Metadata(tokenOut).decimals(),
            rounding: OperationsLib.Rounding.Ceil
        });

        _burn({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _shares: _shares,
            _totalShares: recipients[_recipient].totalShares,
            _tokenDecimals: IERC20Metadata(tokenOut).decimals()
        });

        // To accurately compute the protocol's fees from the yield generated by the strategy, we first need to
        // determine the percentage of the initial investment being withdrawn. This allows us to assess whether any
        // yield has been generated beyond the initial investment.
        params.investment =
            (recipients[_recipient].investedAmount * params.shareRatio) / (10 ** IERC20Metadata(tokenOut).decimals());

        params.balanceBefore = IERC20(tokenIn).balanceOf(_recipient);

        IHolding(_recipient).approve({ _tokenAddress: tokenOut, _destination: address(pendleRouter), _amount: _shares });
        (bool success, bytes memory returnData) = IHolding(_recipient).genericCall({
            _contract: address(pendleRouter),
            _call: abi.encodeCall(
                IPActionAddRemoveLiqV3.removeLiquiditySingleToken,
                (
                    _recipient, // receiverOfUnderlying
                    pendleMarket,
                    _shares,
                    params.output,
                    params.limit
                )
            )
        });

        // Assert the call succeeded.
        if (!success) revert(OperationsLib.getRevertMsg(returnData));
        params.balanceAfter = IERC20(tokenIn).balanceOf(_recipient);

        // Take protocol's fee if any.
        params.balanceDiff = params.balanceAfter - params.balanceBefore;
        (params.performanceFee,,) = _getStrategyManager().strategyInfo(address(this));
        if (params.balanceDiff > params.investment && params.performanceFee != 0) {
            uint256 rewardAmount = params.balanceDiff - params.investment;
            uint256 fee = OperationsLib.getFeeAbsolute(rewardAmount, params.performanceFee);
            if (fee > 0) {
                address feeAddr = _getManager().feeAddress();
                emit FeeTaken(tokenIn, feeAddr, fee);
                IHolding(_recipient).transfer(tokenIn, feeAddr, fee);
            }
        }

        jigsawStaker.withdraw({ _user: _recipient, _amount: _shares });

        recipients[_recipient].totalShares -= _shares;
        recipients[_recipient].investedAmount = params.investment > recipients[_recipient].investedAmount
            ? 0
            : recipients[_recipient].investedAmount - params.investment;

        emit Withdraw({ asset: _asset, recipient: _recipient, shares: _shares, amount: params.balanceDiff });
        return (params.balanceDiff, params.investment);
    }

    /**
     * @notice Claims rewards from the Pendle Pool.
     * @return claimedAmounts The amounts of rewards claimed.
     * @return rewardsList The addresses of the reward tokens.
     */
    function claimRewards(
        address _recipient,
        bytes calldata
    ) external override returns (uint256[] memory claimedAmounts, address[] memory rewardsList) {
        (bool success, bytes memory returnData) = IHolding(_recipient).genericCall({
            _contract: pendleMarket,
            _call: abi.encodeWithSignature("redeemRewards(address)", _recipient)
        });

        if (!success) revert(OperationsLib.getRevertMsg(returnData));

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
