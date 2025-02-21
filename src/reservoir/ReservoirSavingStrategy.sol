// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManagerContainer } from "@jigsaw/src/interfaces/core/IManagerContainer.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";

import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";

import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";
import { ICreditEnforcer } from "./interfaces/ICreditEnforcer.sol";
import { IPegStabilityModule } from "./interfaces/IPegStabilityModule.sol";
import { ISavingModule } from "./interfaces/ISavingModule.sol";

import { StrategyBaseUpgradeable } from "../StrategyBaseUpgradeable.sol";

/**
 * @title ReservoirSavingStrategy
 * @dev Strategy used for srUSD minting.
 * @author Hovooo (@hovooo)
 */
contract ReservoirSavingStrategy is IStrategy, StrategyBaseUpgradeable {
    using SafeERC20 for IERC20;

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     */
    struct InitializerParams {
        address owner; // The address of the initial owner of the Strategy contract
        address managerContainer; // The address of the contract that contains the manager contract
        address creditEnforcer; // The address of the Reservoir's CreditEnforcer contract
        address pegStabilityModule; // The Reservoir's PegStabilityModule contract.
        address savingModule; // The Reservoir's SavingModule contract.
        address rUSD; // The Reservoir's rUSD stablecoin.
        address stakerFactory; // The address of the StakerLightFactory contract
        address jigsawRewardToken; // The address of the Jigsaw reward token associated with the strategy
        uint256 jigsawRewardDuration; // The address of the initial Jigsaw reward distribution duration for the strategy
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of Reservoir's receipt token
    }

    /**
     * @notice Struct containing parameters for a withdrawal operation.
     */
    struct WithdrawParams {
        uint256 shareRatio; // The share ratio representing the proportion of the total investment owned by the user.
        uint256 assetsToWithdraw; // The amount of assets to withdraw based on the share ratio.
        uint256 investment; // The amount of funds invested by the user.
        uint256 balanceBefore; // The user's balance in the system before the withdrawal transaction.
        uint256 balanceAfter; // The user's balance in the system after the withdrawal transaction is completed.
        uint256 balanceDiff; // The difference between balanceAfter and balanceBefore.
        uint256 performanceFee; // Protocol's performanceFee applied to extra generated yield.
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
     * @notice The tokenOut address (srUSD) for the strategy.
     */
    address public override tokenOut;

    /**
     * @notice The Reservoir's reward token offered to users.
     */
    address public override rewardToken;

    /**
     * @notice The receipt token associated with this strategy.
     */
    IReceiptToken public override receiptToken;

    /**
     * @notice The Reservoir's CreditEnforcer contract.
     */
    ICreditEnforcer public creditEnforcer;

    /**
     * @notice The Reservoir's PegStabilityModule contract.
     */
    address public pegStabilityModule;

    /**
     * @notice The Reservoir's SavingModule contract.
     */
    address public savingModule;

    /**
     * @notice The Reservoir's Stablecoin rUSD.
     */
    address public rUSD;

    /**
     * @notice The Jigsaw Rewards Controller contract.
     */
    IStakerLight public jigsawStaker;

    /**
     * @notice The number of decimals of the strategy's shares.
     */
    uint256 public override sharesDecimals;

    /**
     * @notice The factor used to adjust values from 18 decimal precision (shares) to 6 decimal precision (USDC).
     */
    uint256 public constant DECIMAL_DIFF = 1e12;

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
     * @notice Initializes the Reservoir Stablecoin Strategy contract with necessary parameters.
     *
     * @dev Configures core components such as manager, tokens, pools, and reward systems
     * needed for the strategy to operate.
     *
     * @dev This function is only callable once due to the `initializer` modifier.
     *
     * @notice Ensures that critical addresses are non-zero to prevent misconfiguration:
     * - `_params.managerContainer` must be valid (`"3065"` error code if invalid).
     * - `_params.creditEnforcer` must be valid (`"3036"` error code if invalid).
     * - `_params.pegStabilityModule` must be valid (`"3036"` error code if invalid).
     * - `_params.tokenIn` and `_params.tokenOut` must be valid (`"3000"` error code if invalid).
     *
     * @param _params Struct containing all initialization parameters:
     * - owner: The address of the initial owner of the Strategy contract.
     * - managerContainer: The address of the contract that contains the manager contract.
     * - creditEnforcer: The address of the Reservoir's CreditEnforcer contract.
     * - pegStabilityModule:  The Reservoir's PegStabilityModule contract.
     * - savingModule:  The Reservoir's SavingModule contract.
     * - rUSD:  The Reservoir's rUSD stablecoin.
     * - stakerFactory: The address of the StakerLightFactory contract.
     * - jigsawRewardToken: The address of the Jigsaw reward token associated with the strategy.
     * - jigsawRewardDuration: The initial duration for the Jigsaw reward distribution.
     * - tokenIn: The address of the LP token used as input for the strategy.
     * - tokenOut: The address of the receipt token received as output from the strategy.
     */
    function initialize(
        InitializerParams memory _params
    ) public initializer {
        require(_params.managerContainer != address(0), "3065");
        require(_params.creditEnforcer != address(0), "3036");
        require(_params.pegStabilityModule != address(0), "3036");
        require(_params.savingModule != address(0), "3036");
        require(_params.rUSD != address(0), "3036");
        require(_params.jigsawRewardToken != address(0), "3000");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        managerContainer = IManagerContainer(_params.managerContainer);
        creditEnforcer = ICreditEnforcer(_params.creditEnforcer);
        pegStabilityModule = _params.pegStabilityModule;
        savingModule = _params.savingModule;
        rUSD = _params.rUSD;
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();
        rewardToken = address(0);

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: _getManager().receiptTokenFactory(),
                _receiptTokenName: "Reservoir Receipt Token",
                _receiptTokenSymbol: "ReRT"
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
    ) external override nonReentrant onlyValidAmount(_amount) onlyStrategyManager returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");

        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });

        uint256 rUsdAmount = _amount;

        // If user deposits USDC, rUSD needs to be minted first to be later used for srUSD minting
        if (_asset != rUSD) {
            uint256 rUsdBalanceBefore = IERC20(rUSD).balanceOf(address(this));

            // Mint rUSD
            OperationsLib.safeApprove({ token: _asset, to: address(pegStabilityModule), value: _amount });
            creditEnforcer.mintStablecoin({ amount: _amount });

            rUsdAmount = IERC20(rUSD).balanceOf(address(this)) - rUsdBalanceBefore;
        }

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_recipient);

        OperationsLib.safeApprove({ token: rUSD, to: address(savingModule), value: rUsdAmount });
        creditEnforcer.mintSavingcoin({ to: _recipient, amount: rUsdAmount });

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
        bytes calldata
    ) external override nonReentrant onlyStrategyManager returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");
        require(_shares <= IERC20(tokenOut).balanceOf(_recipient), "2002");

        WithdrawParams memory params = WithdrawParams({
            shareRatio: 0,
            assetsToWithdraw: 0,
            investment: 0,
            balanceBefore: 0,
            balanceAfter: 0,
            balanceDiff: 0,
            performanceFee: 0
        });

        uint256 tokenOutDecimals = IERC20Metadata(tokenOut).decimals();

        params.shareRatio = OperationsLib.getRatio({
            numerator: _shares,
            denominator: recipients[_recipient].totalShares,
            precision: tokenOutDecimals,
            rounding: OperationsLib.Rounding.Floor
        });

        _burn({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _shares: _shares,
            _totalShares: recipients[_recipient].totalShares,
            _tokenDecimals: tokenOutDecimals
        });

        params.investment = (recipients[_recipient].investedAmount * params.shareRatio) / 10 ** tokenOutDecimals;

        // Since srUSD's price fluctuates relative to rUSD, we must calculate the current rUSD equivalent for the given
        // srUSD amount. The Saving Module's `previewRedeem` function does not factor in the redeem fee applied during
        // actual redemption. To get an accurate `assetsToWithdraw` value, we replicate the fee deduction logic here.
        params.assetsToWithdraw = recipients[_recipient].totalShares * params.shareRatio
            * ISavingModule(savingModule).currentPrice() / 1e8 * 1e6 / (1e6 + ISavingModule(savingModule).redeemFee())
            / 10 ** tokenOutDecimals;

        params.balanceBefore = IERC20(tokenIn).balanceOf(_recipient);
        uint256 rUsdBalanceBefore = IERC20(rUSD).balanceOf(address(this));

        IHolding(_recipient).approve({
            _tokenAddress: tokenOut,
            _destination: savingModule,
            _amount: params.assetsToWithdraw
        });

        (bool success, bytes memory returnData) = IHolding(_recipient).genericCall({
            _contract: savingModule,
            _call: abi.encodeCall(
                ISavingModule.redeem, (_asset == rUSD ? _recipient : address(this), params.assetsToWithdraw)
            )
        });
        require(success, OperationsLib.getRevertMsg(returnData));

        // Get USDC back if it was used as tokenIn
        if (_asset != rUSD) {
            uint256 rUsdRedemptionAmount = IERC20(rUSD).balanceOf(address(this)) - rUsdBalanceBefore;
            OperationsLib.safeApprove({ token: rUSD, to: address(pegStabilityModule), value: rUsdRedemptionAmount });
            IPegStabilityModule(pegStabilityModule).redeem({
                to: _recipient,
                amount: rUsdRedemptionAmount / DECIMAL_DIFF
            });
        }

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
     * @notice Claims rewards from the Reservoir Pool.
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
}
