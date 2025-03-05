// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAutoPxEth } from "./interfaces/IAutoPxEth.sol";
import { IPirexEth } from "./interfaces/IPirexEth.sol";
import { IWETH9 } from "./interfaces/IWETH9.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManagerContainer } from "@jigsaw/src/interfaces/core/IManagerContainer.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";

import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";

import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";

import { StrategyBaseUpgradeable } from "../StrategyBaseUpgradeable.sol";

/**
 * @title DineroStrategy
 * @dev Strategy used for Dinero protocol's autoPxEth.
 * @author Hovooo (@hovooo)
 */
contract DineroStrategy is IStrategy, StrategyBaseUpgradeable {
    using SafeERC20 for IERC20;

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     */
    struct InitializerParams {
        address owner; // The address of the initial owner of the Strategy contract
        address managerContainer; // The address of the contract that contains the manager contract
        address stakerFactory; // The address of the StakerLightFactory contract
        address pirexEth; // The address of the PirexEth
        address autoPirexEth; // The address of the AutoPirexEth
        address jigsawRewardToken; // The address of the Jigsaw reward token associated with the strategy
        uint256 jigsawRewardDuration; // The address of the initial Jigsaw reward distribution duration for the strategy
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of the PirexEth receipt token (pxEth)
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
    }

    // -- Errors --

    error OperationNotSupported();
    error InvalidEthSender(address sender);

    // -- Events --

    /**
     * @notice Emitted when a performance fee is taken.
     * @param token The token from which the fee is taken.
     * @param feeAddress The address that receives the fee.
     * @param amount The amount of the fee.
     */
    event FeeTaken(address indexed token, address indexed feeAddress, uint256 amount);

    /**
     * @notice Event indicating that the contract received Ether.
     *
     * @param from The address that sent the Ether.
     * @param amount The amount of Ether received (in wei).
     */
    event Received(address indexed from, uint256 amount);

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
     * @notice Initializes the Dinero Strategy contract with necessary parameters.
     *
     * @dev Configures core components such as manager, tokens, pools needed for the strategy to operate.
     *
     * @dev This function is only callable once due to the `initializer` modifier.
     *
     * @notice Ensures that critical addresses are non-zero to prevent misconfiguration:
     * - `_params.managerContainer` must be valid (`"3065"` error code if invalid).
     * - `_params.pirexEth` must be valid (`"3036"` error code if invalid).
     * - `_params.autoPirexEth` must be valid (`"3036"` error code if invalid).
     * - `_params.rewardsController` must be valid (`"3036"` error code if invalid).
     * - `_params.tokenIn` and `_params.tokenOut` must be valid (`"3000"` error code if invalid).
     *
     * @param _params Struct containing all initialization parameters:
     * - owner: The address of the initial owner of the Strategy contract.
     * - managerContainer: The address of the contract that contains the manager contract.
     * - stakerFactory: The address of the StakerLightFactory contract.
     * - pirexEth: The address of the PirexEth.
     * - autoPirexEth: The address of the AutoPirexEth.
     * - jigsawRewardToken: The address of the Jigsaw reward token associated with the strategy.
     * - jigsawRewardDuration: The initial duration for the Jigsaw reward distribution.
     * - tokenIn: The address of the LP token used as input for the strategy.
     * - tokenOut: The address of the PirexEth receipt token (pxEth).
     */
    function initialize(
        InitializerParams memory _params
    ) public initializer {
        require(_params.managerContainer != address(0), "3065");
        require(_params.pirexEth != address(0), "3036");
        require(_params.autoPirexEth != address(0), "3000");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        managerContainer = IManagerContainer(_params.managerContainer);
        pirexEth = IPirexEth(_params.pirexEth);
        autoPirexEth = IAutoPxEth(_params.autoPirexEth);
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: _getManager().receiptTokenFactory(),
                _receiptTokenName: "PirexEth Strategy Receipt Token",
                _receiptTokenSymbol: "apxEth"
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
        _mint({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _amount: shares,
            _tokenDecimals: IERC20Metadata(tokenOut).decimals()
        });

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
    ) external override nonReentrant onlyStrategyManager returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");
        require(_shares <= IERC20(tokenOut).balanceOf(_recipient), "2002");

        WithdrawParams memory params = WithdrawParams({
            shareRatio: 0,
            investment: 0,
            balanceBefore: 0,
            balanceAfter: 0,
            balanceDiff: 0,
            performanceFee: 0
        });

        // Calculate the ratio between all user's shares and the amount of shares used for withdrawal.
        params.shareRatio = OperationsLib.getRatio({
            numerator: _shares,
            denominator: recipients[_recipient].totalShares,
            precision: IERC20Metadata(tokenOut).decimals(),
            rounding: OperationsLib.Rounding.Floor
        });

        // Burn Strategy's receipt tokens used for withdrawal.
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

        // Redeem pxETH via the AutoPirexEth contract using the recipient's `IHolding` contract.
        (bool success, bytes memory returnData) = IHolding(_recipient).genericCall({
            _contract: address(autoPirexEth),
            _call: abi.encodeCall(IAutoPxEth.redeem, (_shares, address(this), _recipient))
        });

        // Ensure the external call was successful and decode any potential revert reason.
        require(success, OperationsLib.getRevertMsg(returnData));

        // Decode the returned data to get the amount of pxETH withdrawn from the AutoPirexEth contract.
        uint256 pxEthWithdrawn = abi.decode(returnData, (uint256));

        // Use the PirexEth contract to instantly redeem the withdrawn pxETH for ETH.
        (uint256 postFeeAmount,) = pirexEth.instantRedeemWithPxEth(pxEthWithdrawn, address(this));

        // Swap ETH back to WETH.
        IWETH9(tokenIn).deposit{ value: postFeeAmount }();

        // Transfer WETH to the `_recipient`.
        IERC20(tokenIn).safeTransfer(_recipient, postFeeAmount);

        // Take protocol's fee if any.
        params.balanceDiff = IERC20(tokenIn).balanceOf(_recipient) - params.balanceBefore;
        (params.performanceFee,,) = _getStrategyManager().strategyInfo(address(this));
        if (params.balanceDiff > params.investment && params.performanceFee != 0) {
            uint256 rewardAmount = params.balanceDiff - params.investment;
            uint256 fee = OperationsLib.getFeeAbsolute(rewardAmount, params.performanceFee);
            if (fee > 0) {
                address feeAddr = _getManager().feeAddress();
                params.balanceDiff -= fee;
                emit FeeTaken(tokenIn, feeAddr, fee);
                IHolding(_recipient).transfer(tokenIn, feeAddr, fee);
            }
        }

        recipients[_recipient].totalShares -= _shares;
        recipients[_recipient].investedAmount = params.investment > recipients[_recipient].investedAmount
            ? 0
            : recipients[_recipient].investedAmount - params.investment;

        emit Withdraw({ asset: _asset, recipient: _recipient, shares: _shares, amount: params.balanceDiff });
        // Register `_recipient`'s withdrawal operation to stop generating jigsaw rewards.
        jigsawStaker.withdraw({ _user: _recipient, _amount: _shares });

        return (params.balanceDiff, params.investment);
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
