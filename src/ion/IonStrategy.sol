// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";

import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";

import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";
import { IIonPool } from "./interfaces/IIonPool.sol";

import { StrategyBaseUpgradeable } from "../StrategyBaseUpgradeable.sol";

/**
 * @title IonStrategy
 * @dev Strategy used for Ion Pool.
 * @author Hovooo (@hovooo)
 */
contract IonStrategy is IStrategy, StrategyBaseUpgradeable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     * @param owner The address of the initial owner of the Strategy contract
     * @param manager The address of the Manager contract
     * @param stakerFactory The address of the StakerLightFactory contract
     * @param ionPool The address of the Ion Pool
     * @param jigsawRewardToken The address of the Jigsaw reward token associated with the strategy
     * @param jigsawRewardDuration The address of the initial Jigsaw reward distribution duration for the strategy
     * @param tokenIn The address of the LP token
     * @dev The `tokenOut` field is not used in the Ion strategy as it is the same as `ionPool`.
     */
    struct InitializerParams {
        address owner;
        address manager;
        address stakerFactory;
        address ionPool;
        address jigsawRewardToken;
        uint256 jigsawRewardDuration;
        address tokenIn;
    }

    // -- Errors --

    error OperationNotSupported();

    // -- State variables --

    /**
     * @notice The LP token address.
     */
    address public override tokenIn;

    /**
     * @notice The Ion receipt token address.
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
     * @notice The Ion Pool contract.
     */
    IIonPool public ionPool;

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
     * @notice Initializes the Ion Strategy contract with necessary parameters.
     *
     * @notice IonPool is an upgradeable contract for each of its markets. This introduces upgrade risk
     * that users should be aware of, as changes to the implementation could affect deposited funds.
     *
     * @dev Configures core components such as manager, tokens, pools, and reward systems
     * needed for the strategy to operate.
     * @dev This function is only callable once due to the `initializer` modifier.
     *
     * @notice Ensures that critical addresses are non-zero to prevent misconfiguration:
     * - `_params.manager` must be valid (`"3065"` error code if invalid).
     * - `_params.ionPool` must be valid (`"3036"` error code if invalid).
     * - `_params.tokenIn` and `_params.tokenOut` must be valid (`"3000"` error code if invalid).
     *
     * @param _params Struct containing all initialization parameters.
     */
    function initialize(
        InitializerParams memory _params
    ) public initializer {
        require(_params.manager != address(0), "3065");
        require(_params.ionPool != address(0), "3036");
        require(_params.tokenIn != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        manager = IManager(_params.manager);
        ionPool = IIonPool(_params.ionPool);
        tokenIn = _params.tokenIn;
        tokenOut = _params.ionPool;
        sharesDecimals = IERC20Metadata(_params.ionPool).decimals();

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: manager.receiptTokenFactory(),
                _receiptTokenName: "Ion Strategy Receipt Token",
                _receiptTokenSymbol: "IoRT"
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
     * @param _data Extra data, e.g., a referral code.
     *
     * @return The amount of receipt tokens obtained.
     * @return The amount of the 'tokenIn()' token.
     */
    function deposit(
        address _asset,
        uint256 _amount,
        address _recipient,
        bytes calldata _data
    ) external override onlyValidAmount(_amount) nonReentrant onlyStrategyManager returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");
        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });
        uint256 balanceBefore = ionPool.normalizedBalanceOf(_recipient);

        // Supply to the Ion Pool on behalf of the `_recipient`.
        IERC20(_asset).forceApprove({ spender: address(ionPool), value: _amount });
        ionPool.supply({
            user: _recipient,
            amount: _amount,
            proof: _data.length > 0 ? abi.decode(_data, (bytes32[])) : new bytes32[](0)
        });

        uint256 shares = ionPool.normalizedBalanceOf(_recipient) - balanceBefore;
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
     * @notice Withdraws deposited funds.
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
        uint256 totalSharesBefore = IIonPool(tokenOut).normalizedBalanceOf(_recipient);
        require(_shares <= totalSharesBefore, "2002");

        WithdrawParams memory params = WithdrawParams({
            shares: _shares,
            totalShares: recipients[_recipient].totalShares,
            shareRatio: 0,
            shareDecimals: sharesDecimals,
            investment: 0,
            assetsToWithdraw: 0, // not used in Ion strategy
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

        // Since Ion generates yield in the same token as the initial deposit (tokenIn), we must calculate the
        // amount of tokenIn (including both the initial deposit and accrued yield) to be withdrawn. To achieve this,
        // we apply the percentage of the user's total shares to be withdrawn relative to their entire shareholding to
        // the available balance in Ion, ensuring the correct proportion of assets is withdrawn.
        params.assetsToWithdraw =
            IIonPool(tokenOut).balanceOf(_recipient) * params.shareRatio / (10 ** params.shareDecimals);

        // To accurately compute the protocol's fees from the yield generated by the strategy, we first need to
        // determine the percentage of the initial investment being withdrawn. This allows us to assess whether any
        // yield has been generated beyond the initial investment.
        params.investment = (recipients[_recipient].investedAmount * params.shareRatio) / (10 ** params.shareDecimals);
        params.balanceBefore = IERC20(tokenIn).balanceOf(_recipient);

        // Perform the withdrawal operation from user's holding address.
        // Note: The `withdraw` function can be paused by Ion protocol, reverting the transaction.
        _genericCall({
            _holding: _recipient,
            _contract: address(ionPool),
            _call: abi.encodeCall(IIonPool.withdraw, (_recipient, params.assetsToWithdraw))
        });

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
        jigsawStaker.withdraw({ _user: _recipient, _amount: params.shares });

        return (params.withdrawnAmount, params.investment, params.yield, params.fee);
    }

    /**
     * @notice Claims rewards from the Ion Pool.
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
