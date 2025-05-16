// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAutoPxEth } from "./interfaces/IAutoPxEth.sol";
import { IPirexEth } from "./interfaces/IPirexEth.sol";
import { IWETH9 } from "./interfaces/IWETH9.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";

import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";

import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";

import { StrategyBaseUpgradeableV2 } from "../StrategyBaseUpgradeableV2.sol";
import { IFeeManager } from "../extensions/interfaces/IFeeManager.sol";

/**
 * @title DineroStrategyV2
 * @dev Strategy used for Dinero protocol's autoPxEth.
 * @author Hovooo (@hovooo)
 * @custom:oz-upgrades-from DineroStrategy
 */
contract DineroStrategyV2 is IStrategy, StrategyBaseUpgradeableV2 {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // -- Errors --

    error OperationNotSupported();
    error InvalidEthSender(address sender);

    // -- Events --

    /**
     * @notice Event indicating that the contract received Ether.
     *
     * @param from The address that sent the Ether.
     * @param amount The amount of Ether received (in wei).
     */
    event Received(address indexed from, uint256 amount);

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     * @param owner The address of the initial owner of the Strategy contract
     * @param feeManager The address of the feeManager contract
     */
    struct InitializerParams {
        address feeManager;
    }

    // -- State variables --

    /**
     * @notice The WETH token is utilized as the input token, which is later unwrapped to ETH and re-wrapped to
     * facilitate Dinero investments.
     */
    address public override tokenIn;

    /**
     * @notice The PirexEth receipt token address.
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
     * @notice The PirexEth contract.
     */
    IPirexEth public pirexEth;

    /**
     * @notice The PirexEth contract.
     */
    IAutoPxEth public autoPirexEth;

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
    mapping(address recipient => IStrategy.RecipientInfo info) public override recipients;

    // -- Constructor --

    constructor() {
        _disableInitializers();
    }

    // -- Initialization --

    /**
     * @custom:oz-upgrades-validate-as-initializer
     *
     * @notice Initializes the Aave Strategy V2 contract with necessary parameters.
     *
     * @dev Configures core components such as manager, tokens, pools, and reward systems
     * needed for the strategy to operate.
     *
     * @dev This function is only callable once due to the `initializer` modifier.
     *
     * @notice Ensures that critical addresses are non-zero to prevent misconfiguration:
     * - `_params.feeManager` must be valid (`"3000"` error code if invalid).
     *
     * @param _params Struct containing all initialization parameters.
     */
    function initialize(
        InitializerParams memory _params
    ) public reinitializer(2) {
        require(_params.feeManager != address(0), "3000");
        feeManager = IFeeManager(_params.feeManager);
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
        bytes calldata
    ) external override nonReentrant onlyValidAmount(_amount) onlyStrategyManager returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_recipient);

        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });

        // Swap WETH to ETH.
        IWETH9(tokenIn).withdraw(_amount);
        // Deposit ETH to mint pxETH and stakes pxETH for autocompounding.
        pirexEth.deposit{ value: _amount }({ receiver: _recipient, shouldCompound: true });

        uint256 shares = IERC20(tokenOut).balanceOf(_recipient) - balanceBefore;
        recipients[_recipient].investedAmount += _amount;
        recipients[_recipient].totalShares += shares;

        // Mint Strategy's receipt tokens to allow later withdrawal.
        _mint({ _receiptToken: receiptToken, _recipient: _recipient, _amount: shares, _tokenDecimals: sharesDecimals });

        // Register `_recipient`'s deposit operation to generate jigsaw rewards.
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
     *
     * @return The amount of the asset obtained from the operation.
     * @return The amount of the 'tokenIn()' token.
     */
    function withdraw(
        uint256 _shares,
        address _recipient,
        address _asset,
        bytes calldata
    ) external override nonReentrant onlyStrategyManager returns (uint256, uint256, int256, uint256) {
        require(_asset == tokenIn, "3001");
        require(_shares <= IERC20(tokenOut).balanceOf(_recipient), "2002");

        WithdrawParams memory params = WithdrawParams({
            shares: _shares,
            totalShares: recipients[_recipient].totalShares,
            shareRatio: 0,
            shareDecimals: sharesDecimals,
            investment: 0,
            assetsToWithdraw: 0, // not used in Dinero strategy
            balanceBefore: 0,
            withdrawnAmount: 0,
            yield: 0,
            fee: 0
        });

        // Calculate the ratio between all user's shares and the amount of shares used for withdrawal.
        params.shareRatio = OperationsLib.getRatio({
            numerator: params.shares,
            denominator: params.totalShares,
            precision: params.shareDecimals,
            rounding: OperationsLib.Rounding.Floor
        });

        // Burn Strategy's receipt tokens used for withdrawal.
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

        // Redeem pxETH via the AutoPirexEth contract using the recipient's `IHolding` contract.
        (, bytes memory returnData) = _genericCall({
            _holding: _recipient,
            _contract: address(autoPirexEth),
            _call: abi.encodeCall(IAutoPxEth.redeem, (_shares, address(this), _recipient))
        });

        // Use the PirexEth contract to instantly redeem the withdrawn pxETH for ETH.
        // Note: The `instantRedeemWithPxEth` function can be paused by PirexEth protocol, reverting the transaction.
        (uint256 postFeeAmount,) = pirexEth.instantRedeemWithPxEth(abi.decode(returnData, (uint256)), address(this));

        // Transfer WETH to the `_recipient`.
        IWETH9(tokenIn).deposit{ value: postFeeAmount }();
        IERC20(tokenIn).safeTransfer(_recipient, postFeeAmount);

        // Get the actually withdrawn amount and calculate the generated yield
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
     * @notice Claims rewards from the PirexEth.
     * @return The amounts of rewards claimed.
     * @return The addresses of the reward tokens.
     */
    function claimRewards(
        address,
        bytes calldata
    ) external pure override returns (uint256[] memory, address[] memory) {
        revert OperationNotSupported();
    }

    // -- Getters --

    /**
     * @notice Returns the address of the receipt token.
     */
    function getReceiptTokenAddress() external view override returns (address) {
        return address(receiptToken);
    }

    // -- Utilities --

    /**
     * @notice Allows the contract to accept incoming Ether transfers.
     * @dev This function is executed when the contract receives Ether with no data in the transaction.
     *
     * @notice Emits:
     * - `Received` event to log the sender's address and the amount received.
     */
    receive() external payable {
        if (msg.sender != address(tokenIn) && msg.sender != address(pirexEth)) revert InvalidEthSender(msg.sender);
        emit Received({ from: msg.sender, amount: msg.value });
    }
}
