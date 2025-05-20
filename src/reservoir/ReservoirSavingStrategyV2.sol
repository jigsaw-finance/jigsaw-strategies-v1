// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";

import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";

import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";
import { ICreditEnforcer } from "./interfaces/ICreditEnforcer.sol";
import { IPegStabilityModule } from "./interfaces/IPegStabilityModule.sol";
import { ISavingModule } from "./interfaces/ISavingModule.sol";

import { StrategyBaseUpgradeableV2 } from "../StrategyBaseUpgradeableV2.sol";
import { IFeeManager } from "../extensions/interfaces/IFeeManager.sol";

/**
 * @title ReservoirSavingStrategyV2
 * @dev Strategy used for srUSD minting.
 * @author Hovooo (@hovooo)
 * @custom:oz-upgrades-from ReservoirSavingStrategy
 */
contract ReservoirSavingStrategyV2 is IStrategy, StrategyBaseUpgradeableV2 {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // -- Errors --

    error OperationNotSupported();

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
     * @notice The precision used for the Reservoir's fee.
     */
    uint256 public constant RESERVOIR_FEE_PRECISION = 1e6;

    /**
     * @notice The precision used for the Reservoir's rUSD price.
     */
    uint256 public constant RESERVOIR_PRICE_PRECISION = 1e8;

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
            IERC20(_asset).forceApprove({ spender: address(pegStabilityModule), value: _amount });
            creditEnforcer.mintStablecoin({ amount: _amount });

            rUsdAmount = IERC20(rUSD).balanceOf(address(this)) - rUsdBalanceBefore;
        }

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_recipient);

        IERC20(rUSD).forceApprove({ spender: address(savingModule), value: rUsdAmount });
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
     * @param _shares The amount of shares to withdraw.
     * @param _recipient The address on behalf of which the funds are withdrawn.
     * @param _asset The token to be withdrawn.
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
            assetsToWithdraw: 0, // not used in Reservoir strategy
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
        // Calculate rUSD to withdraw for specified shares, accounting for srUSD price fluctuation and redeem fee.
        params.assetsToWithdraw = getAssetsToWithdraw({
            _shares: params.shares,
            _currentPrice: ISavingModule(savingModule).currentPrice(),
            _redeemFee: ISavingModule(savingModule).redeemFee()
        });

        params.balanceBefore = IERC20(tokenIn).balanceOf(_recipient);
        uint256 rUsdBalanceBefore = IERC20(rUSD).balanceOf(address(this));

        // Approve the amount of shares to be redeemed and call redeem on the SavingModule contract.
        IHolding(_recipient).approve({ _tokenAddress: tokenOut, _destination: savingModule, _amount: _shares });
        _genericCall({
            _holding: _recipient,
            _contract: savingModule,
            _call: abi.encodeCall(
                ISavingModule.redeem, (_asset == rUSD ? _recipient : address(this), params.assetsToWithdraw)
            )
        });

        // Get USDC back if it was used as tokenIn
        if (_asset != rUSD) {
            uint256 rUsdRedemptionAmount = IERC20(rUSD).balanceOf(address(this)) - rUsdBalanceBefore;
            IERC20(rUSD).forceApprove({ spender: address(pegStabilityModule), value: rUsdRedemptionAmount });

            // Note: The `redeem` function can be paused by Reservoir protocol, making USDC unclaimable.
            // Note: This redemption process may leave a small dust amount of rUSD in the contract
            IPegStabilityModule(pegStabilityModule).redeem({
                to: _recipient,
                amount: rUsdRedemptionAmount / DECIMAL_DIFF
            });
        }

        // Take protocol's fee if any.
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
     * @notice Previews the amount of srUSD that would be burned for a given redemption
     * @param _amount The amount of assets to redeem
     * @param _currentPrice The current price of srUSD
     * @param _redeemFee The current redemption fee
     * @return srUSDToBurn The amount of srUSD that would be burned
     */
    function _previewRedeem(
        uint256 _amount,
        uint256 _currentPrice,
        uint256 _redeemFee
    ) internal pure returns (uint256 srUSDToBurn) {
        // Step 1: Calculate the base amount of srUSD needed for the redemption
        // We use Math.ceilDiv to round up, ensuring we don't underestimate the shares needed
        srUSDToBurn = Math.ceilDiv(_amount * RESERVOIR_PRICE_PRECISION, _currentPrice);

        // Step 2: Apply the redemption fee to get the total srUSD that will be burned
        // This accounts for the fee taken by the Reservoir protocol during redemption
        srUSDToBurn = srUSDToBurn * (1e6 + _redeemFee) / 1e6;
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
     * @notice Calculates the amount of assets to withdraw based exactly on specified shares amount
     * @param _shares The amount of shares to convert to assets
     * @param _currentPrice The current price of srUSD
     * @param _redeemFee The current redemption fee
     * @return assetsToWithdraw The amount of assets that can be withdrawn
     */
    function getAssetsToWithdraw(
        uint256 _shares,
        uint256 _currentPrice,
        uint256 _redeemFee
    ) public pure returns (uint256 assetsToWithdraw) {
        // Initial estimate: Convert shares to assets considering the current price and redemption fee
        // This formula gives us a starting point that's likely close to the correct value
        assetsToWithdraw = (_shares * _currentPrice * RESERVOIR_FEE_PRECISION)
            / (RESERVOIR_PRICE_PRECISION * (RESERVOIR_FEE_PRECISION + _redeemFee));

        // Decrement the assets amount until we find the maximum valid withdrawal
        // This ensures we don't try to withdraw more than specified shares
        while (_previewRedeem(assetsToWithdraw, _currentPrice, _redeemFee) > _shares) {
            assetsToWithdraw--;
        }
    }

    /**
     * @notice Returns the address of the receipt token.
     */
    function getReceiptTokenAddress() external view override returns (address) {
        return address(receiptToken);
    }
}
