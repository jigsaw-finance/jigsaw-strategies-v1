// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";

import { StrategyBaseUpgradeableV2 } from "../StrategyBaseUpgradeableV2.sol";

import { IFeeManager } from "../extensions/interfaces/IFeeManager.sol";
import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";
import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";

/**
 * @title MorphoStrategy
 * @dev Strategy used to invest in Morpho Vaults.
 * @notice Implements deposit and withdrawal for Morpho's Vaults.
 * @author Hovooo (@hovooo)
 */
contract MorphoStrategy is IStrategy, StrategyBaseUpgradeableV2 {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     * @param owner The address of the initial owner of the Strategy contract.
     * @param manager The address of the Manager contract.
     * @param stakerFactory The address of the StakerLightFactory contract.
     * @param jigsawRewardToken The address of the Jigsaw reward token associated with the strategy.
     * @param jigsawRewardDuration The initial Jigsaw reward distribution duration for the strategy.
     * @param tokenIn The address of the LP token.
     * @param tokenOut The address of Elixir's receipt token.
     * @param feeManager The address of the feeManager contract.
     */
    struct InitializerParams {
        address owner;
        address manager;
        address stakerFactory;
        address jigsawRewardToken;
        uint256 jigsawRewardDuration;
        address tokenIn;
        address tokenOut;
        address feeManager;
    }

    // -- Errors --

    /**
     * @notice Thrown when the number of shares received is less than the minimum specified by the user.
     * @param sharesReceived The actual number of shares received from the operation.
     * @param minShares The minimum acceptable number of shares to be received.
     */
    error SharesTooLow(uint256 sharesReceived, uint256 minShares);

    /**
     * @notice Thrown when the amount of assets received is less than the minimum specified by the user.
     * @param assetsReceived The actual amount of assets received from the withdrawal.
     * @param minTokenOut The minimum acceptable amount of assets to be received.
     */
    error AssetsTooLow(uint256 assetsReceived, uint256 minTokenOut);

    /**
     * @notice Thrown when an unsupported operation is attempted.
     */
    error OperationNotSupported();

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
     * @notice The reward token offered to users.
     */
    address public override rewardToken;

    /**
     * @notice The receipt token associated with this strategy.
     */
    IReceiptToken public override receiptToken;

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
     * @dev Configures core components for the strategy to operate.
     * @dev This function is only callable once due to the `initializer` modifier.
     * @dev Ensures that critical addresses are non-zero to prevent misconfiguration.
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
        require(_params.feeManager != address(0), "3000");
        require(IERC4626(_params.tokenOut).asset() == _params.tokenIn, "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        manager = IManager(_params.manager);
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();
        rewardToken = address(0);
        feeManager = IFeeManager(_params.feeManager);

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: manager.receiptTokenFactory(),
                _receiptTokenName: "Morpho Receipt Token",
                _receiptTokenSymbol: "MoRT"
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
     * @param _data Encoded amount of minimum shares to receive for the given `_amount` of `_asset`.
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

        uint256 minShares = abi.decode(_data, (uint256));
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_recipient);

        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });
        IERC20(_asset).forceApprove({ spender: tokenOut, value: _amount });
        IERC4626(tokenOut).deposit({ assets: _amount, receiver: _recipient });

        uint256 shares = IERC20(tokenOut).balanceOf(_recipient) - balanceBefore;
        if (shares < minShares) revert SharesTooLow({ sharesReceived: shares, minShares: minShares });

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
     * @dev Note: If Morpho lacks sufficient liquidity to process the withdrawal, this transaction will revert.
     *
     * @param _shares The amount of shares to withdraw.
     * @param _recipient The address on behalf of which the funds are withdrawn.
     * @param _asset The token to be withdrawn.
     * @param _data  Encoded minimum amount of `_asset` to receive for given `_shares`.
     *
     * @return withdrawnAmount The actual amount of `_asset` withdrawn from the strategy.
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
            balanceBefore: IERC20(tokenIn).balanceOf(_recipient),
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
        _genericCall({
            _holding: _recipient,
            _contract: tokenOut,
            _call: abi.encodeCall(IERC4626.redeem, (params.shares, _recipient, _recipient))
        });

        params.withdrawnAmount = IERC20(tokenIn).balanceOf(_recipient) - params.balanceBefore;
        (uint256 minTokenOut) = abi.decode(_data, (uint256));
        if (params.withdrawnAmount < minTokenOut) {
            revert AssetsTooLow({ assetsReceived: params.withdrawnAmount, minTokenOut: minTokenOut });
        }

        // Take protocol's fee from generated yield if any.
        params.yield = params.withdrawnAmount.toInt256() - params.investment.toInt256();
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
     * @notice Rewards are claimed offchain.
     * @dev Please, consult https://docs.morpho.org/build/earn/tutorials/rewards for more information.
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

    /**
     * @notice Returns the expected amount of ERC4626 shares minted for a deposit of `assets`.
     * @dev Proxies to the underlying ERC4626 vault's `previewDeposit`.
     * @param assets The amount of underlying assets to deposit.
     * @return shares The expected number of shares that would be minted.
     */
    function previewDeposit(
        uint256 assets
    ) external view returns (uint256 shares) {
        return IERC4626(tokenOut).previewDeposit(assets);
    }

    /**
     * @notice Returns the expected amount of underlying assets received for redeeming `shares`.
     * @dev Proxies to the underlying ERC4626 vault's `previewRedeem`.
     * @param shares The amount of shares to redeem.
     * @return assets The expected amount of underlying assets that would be received.
     */
    function previewWithdraw(
        uint256 shares
    ) external view returns (uint256 assets) {
        return IERC4626(tokenOut).previewRedeem(shares);
    }
}
