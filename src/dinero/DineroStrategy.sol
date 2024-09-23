// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IHolding} from "@jigsaw/src/interfaces/core/IHolding.sol";
import {IManagerContainer} from "@jigsaw/src/interfaces/core/IManagerContainer.sol";
import {IReceiptToken} from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import {IStrategy} from "@jigsaw/src/interfaces/core/IStrategy.sol";

import {OperationsLib} from "../libraries/OperationsLib.sol";
import {StrategyConfigLib} from "../libraries/StrategyConfigLib.sol";

import {IStakerLight} from "../staker/interfaces/IStakerLight.sol";
import {IStakerLightFactory} from "../staker/interfaces/IStakerLightFactory.sol";

import {StrategyBaseUpgradeable} from "../StrategyBaseUpgradeable.sol";

/**
 * @title DineroStrategy
 * @dev Strategy used for PirexEth.
 * @author Hovooo (@hovooo)
 */
contract DineroStrategy is IStrategy, StrategyBaseUpgradeable {
    using SafeERC20 for IERC20;


    // Mainnet wETH
    IWETH9 public weth;

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     */
    struct InitializerParams {
        address owner; // The address of the initial owner of the Strategy contract
        address managerContainer; // The address of the contract that contains the manager contract
        address stakerFactory; // The address of the StakerLightFactory contract
        address pirexEth; // The address of the PirexEth
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

    /**
     * @notice Emitted when the PirexEth address is updated.
     * @param _old The old PirexEth address.
     * @param _new The new PirexEth address.
     */
    event pirexEthUpdated(address indexed _old, address indexed _new);

    // -- State variables --

    /**
     * @notice The LP token address.
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
     * @notice The Jigsaw Rewards Controller contract.
     */
    IStakerLight public jigsawStaker;

    /**
     * @notice The number of decimals of the strategy's shares.
     */
    uint256 public override sharesDecimals;

    /**
     * @notice The total investments in the strategy.
     */
    uint256 public totalInvestments;

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
     * @notice Initializer for the Dinero Strategy.
     */
    function initialize(InitializerParams memory _params) public initializer {
        require(_params.managerContainer != address(0), "3065");
        require(_params.pirexEth != address(0), "3036");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");

        __StrategyBase_init({_initialOwner: _params.owner});

        managerContainer = IManagerContainer(_params.managerContainer);
        pirexEth = IPirexEth(_params.pirexEth);
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();

        weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _receiptTokenFactory: _getManager().receiptTokenFactory(),
                _receiptTokenName: "PirexEth Strategy Receipt Token",
                _receiptTokenSymbol: "pxEth"
            })
        );

        jigsawStaker = IStakerLight(
            IStakerLightFactory(_params.stakerFactory).createStakerLight({
                _initialOwner: _params.owner,
                _holdingManager: _getManager().holdingManager(),
                _tokenIn: address(receiptToken),
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
     * @dev Some strategies won't return any receipt tokens; in this case, 'tokenOutAmount' will be 0.
     * @dev 'tokenInAmount' will be equal to '_amount' if '_asset' is the same as the strategy's 'tokenIn()'.
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
    ) external override onlyValidAmount(_amount) onlyStrategyManager nonReentrant returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");

        IHolding(_recipient).transfer({_token: _asset, _to: address(this), _amount: _amount});

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_recipient);

        weth.withdraw(_amount);

        //OperationsLib.safeApprove({ token: _asset, to: address(ionPool), value: _amount });
        pirexEth.deposit{value: _amount}({receiver: _recipient, shouldCompound: false});

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(_recipient);

        recipients[_recipient].investedAmount += balanceAfter - balanceBefore;
        recipients[_recipient].totalShares += balanceAfter - balanceBefore;
        totalInvestments += balanceAfter - balanceBefore;

        _mint({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _amount: balanceAfter - balanceBefore,
            _tokenDecimals: IERC20Metadata(tokenOut).decimals()
        });

        jigsawStaker.deposit({_user: _recipient, _amount: recipients[_recipient].investedAmount});

        emit Deposit({
            asset: _asset,
            tokenIn: tokenIn,
            assetAmount: _amount,
            tokenInAmount: _amount,
            shares: balanceAfter - balanceBefore,
            recipient: _recipient
        });

        return (balanceAfter - balanceBefore, _amount);
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
        bytes calldata
    ) external override onlyStrategyManager nonReentrant returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");
        require(_shares <= IERC20(tokenOut).balanceOf(_recipient), "2002");

        WithdrawParams memory params =
                        WithdrawParams({shareRatio: 0, investment: 0, balanceBefore: 0, balanceAfter: 0});

        params.shareRatio = OperationsLib.getRatio({
            numerator: _shares,
            denominator: recipients[_recipient].totalShares,
            precision: IERC20Metadata(tokenOut).decimals()
        });

        _burn({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _shares: _shares,
            _totalShares: recipients[_recipient].totalShares,
            _tokenDecimals: IERC20Metadata(tokenOut).decimals()
        });

        params.investment =
            (recipients[_recipient].investedAmount * params.shareRatio) / (10 ** IERC20Metadata(tokenOut).decimals());

        params.balanceBefore = IERC20(tokenIn).balanceOf(_recipient);

        (bool success, bytes memory returnData) = IHolding(_recipient).genericCall({
            _contract: address(pirexEth),
            _call: abi.encodeWithSignature(
                "instantRedeemWithPxEth(uint256,address)",
                _shares, // amount of underlying to redeem
                address(this)  // receiverOfUnderlying
            )
        });
        // Assert the call succeeded.
        require(success, OperationsLib.getRevertMsg(returnData));

        uint256 postFeeAmount = payable(address(this)).balance;

        // Swap ETH back to WETH
        weth.deposit{value: postFeeAmount}();

        // Transfer WETH to _recipient
        IERC20(tokenIn).approve(_recipient, postFeeAmount);
        IERC20(tokenIn).transfer(_recipient, postFeeAmount);

        // Assert the call succeeded.
        params.balanceAfter = IERC20(tokenIn).balanceOf(_recipient);

        _extractTokenInRewards({
            _ratio: params.shareRatio,
            _result: params.balanceAfter - params.balanceBefore,
            _recipient: _recipient,
            _decimals: IERC20Metadata(tokenOut).decimals()
        });

        jigsawStaker.withdraw({_user: _recipient, _amount: recipients[_recipient].investedAmount});

        recipients[_recipient].totalShares =
            _shares > recipients[_recipient].totalShares ? 0 : recipients[_recipient].totalShares - _shares;
        recipients[_recipient].investedAmount = params.investment > recipients[_recipient].investedAmount
            ? 0
            : recipients[_recipient].investedAmount - params.investment;
        totalInvestments =
            params.balanceAfter - params.balanceBefore > totalInvestments ? 0 : totalInvestments - params.investment;

        emit Withdraw({
            asset: _asset,
            recipient: _recipient,
            shares: _shares,
            amount: params.balanceAfter - params.balanceBefore
        });
        return (params.balanceAfter - params.balanceBefore, params.investment);
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
     * @notice Sends tokenIn rewards to the fee address.
     *
     * @param _ratio The ratio of the shares to total shares.
     * @param _result The _result of the balance change.
     * @param _recipient The address of the recipient.
     * @param _decimals The number of decimals of the token.
     */
    function _extractTokenInRewards(uint256 _ratio, uint256 _result, address _recipient, uint256 _decimals) internal {
        if (_ratio > (10 ** _decimals) && _result < recipients[_recipient].investedAmount) return;
        uint256 rewardAmount = 0;
        if (_ratio >= (10 ** _decimals)) rewardAmount = _result - recipients[_recipient].investedAmount;
        if (rewardAmount == 0) return;

        (uint256 performanceFee,,) = _getStrategyManager().strategyInfo(address(this));
        uint256 fee = OperationsLib.getFeeAbsolute(rewardAmount, performanceFee);

        if (fee > 0) {
            address feeAddr = _getManager().feeAddress();
            emit FeeTaken(tokenIn, feeAddr, fee);
            IHolding(_recipient).transfer(tokenIn, feeAddr, fee);
        }
    }

    /**
     * @notice Receives ETH.
     */
    receive() external payable {}

    /**
     * @notice Fallback ETH.
     */
    fallback() external payable {}

}

interface IPirexEth {
    /**
    * @notice Handle pxETH minting in return for ETH deposits
    * @dev    This function handles the minting of pxETH in return for ETH deposits.
    * @param  receiver        address  Receiver of the minted pxETH or apxEth
    * @param  shouldCompound  bool     Whether to also compound into the vault
    * @return postFeeAmount   uint256  pxETH minted for the receiver
    * @return feeAmount       uint256  pxETH distributed as fees
    */
    function deposit(address receiver, bool shouldCompound) external payable
    returns (uint256 postFeeAmount, uint256 feeAmount);

    /**
    * @notice Instant redeem back ETH using pxETH
    * @dev    This function burns pxETH, calculates fees, and transfers ETH to the receiver.
    * @param  assets        uint256   Amount of pxETH to redeem.
    * @param  receiver      address   Address of the ETH receiver.
    * @return postFeeAmount  uint256   Post-fee amount for the receiver.
    * @return feeAmount      uint256  Fee amount sent to the PirexFees.
    */
    function instantRedeemWithPxEth(uint256 assets, address receiver)
    external returns (uint256 postFeeAmount, uint256 feeAmount);
}

/// @title Interface for WETH9
interface IWETH9 is IERC20 {
    // Events
    /**
     * @notice Event emitted when ETH is deposited, minting pxETH, and optionally compounding into the vault.
     * @dev    Use this event to log details about the deposit, including the caller's address, the receiver's address, whether compounding occurred, the deposited amount, received pxETH amount, and fee amount.
     * @param  caller          address  indexed  Address of the entity initiating the deposit.
     * @param  receiver        address  indexed  Address of the receiver of the minted pxETH or apxEth.
     * @param  shouldCompound  bool     indexed  Boolean indicating whether compounding into the vault occurred.
     * @param  deposited       uint256           Amount of ETH deposited.
     * @param  receivedAmount  uint256           Amount of pxETH minted for the receiver.
     * @param  feeAmount       uint256           Amount of pxETH distributed as fees.
     */
    event Deposit(
        address indexed caller,
        address indexed receiver,
        bool indexed shouldCompound,
        uint256 deposited,
        uint256 receivedAmount,
        uint256 feeAmount
    );

    /**
     * @notice Event emitted when a redemption is initiated by burning pxETH in return for upxETH.
     * @dev    Use this event to log details about the redemption initiation, including the redeemed asset amount, post-fee amount, and the receiver's address.
     * @param  assets         uint256           Amount of pxETH burnt for the redemption.
     * @param  postFeeAmount  uint256           Amount of pxETH distributed to the receiver after deducting fees.
     * @param  receiver       address  indexed  Address of the receiver of the upxETH.
     */
    event InitiateRedemption(
        uint256 assets,
        uint256 postFeeAmount,
        address indexed receiver
    );

    /**
     * @notice Event emitted when ETH is redeemed using UpxETH.
     * @dev    Use this event to log details about the redemption, including the tokenId, redeemed asset amount, and the receiver's address.
     * @param  tokenId   uint256           Identifier for the redemption batch.
     * @param  assets    uint256           Amount of ETH redeemed.
     * @param  receiver  address  indexed  Address of the receiver of the redeemed ETH.
     */
    event RedeemWithUpxEth(
        uint256 tokenId,
        uint256 assets,
        address indexed receiver
    );

    /**
     * @notice Event emitted when pxETH is redeemed for ETH with fees.
     * @dev    Use this event to log details about pxETH redemption, including the redeemed asset amount, post-fee amount, and the receiver's address.
     * @param  assets         uint256           Amount of pxETH redeemed.
     * @param  postFeeAmount  uint256           Amount of ETH received by the receiver after deducting fees.
     * @param  _receiver      address  indexed  Address of the receiver of the redeemed ETH.
     */
    event RedeemWithPxEth(
        uint256 assets,
        uint256 postFeeAmount,
        address indexed _receiver
    );

    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint) external;
}

