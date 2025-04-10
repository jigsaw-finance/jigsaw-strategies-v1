// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAToken } from "@aave/v3-core/interfaces/IAToken.sol";
import { IPool } from "@aave/v3-core/interfaces/IPool.sol";
import { IRewardsController } from "@aave/v3-periphery/rewards/interfaces/IRewardsController.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";

import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";

import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";

import { StrategyBaseUpgradeable } from "../StrategyBaseUpgradeable.sol";

/**
 * @title AaveV3Strategy
 * @dev Strategy used for Aave lending pool.
 * @author Hovooo (@hovooo)
 */
contract AaveV3Strategy is IStrategy, StrategyBaseUpgradeable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     * @param owner The address of the initial owner of the Strategy contract
     * @param manager The address of the Manager contract
     * @param stakerFactory The address of the StakerLightFactory contract
     * @param rewardToken The address of the Aave reward token associated with the strategy
     * @param jigsawRewardToken The address of the Jigsaw reward token associated with the strategy
     * @param jigsawRewardDuration Initial Jigsaw reward distribution duration for the strategy
     * @param tokenIn The address of the LP token
     * @param tokenOut The address of the Aave receipt token (aToken)
     * @param lendingPool The address of the Aave Lending Pool
     * @param rewardsController The address of the Aave Rewards Controller
     */
    struct InitializerParams {
        address owner;
        address manager;
        address stakerFactory;
        address rewardToken;
        address jigsawRewardToken;
        uint256 jigsawRewardDuration;
        address tokenIn;
        address tokenOut;
        address lendingPool;
        address rewardsController;
    }

    // -- State variables --

    /**
     * @notice The LP token address.
     */
    address public override tokenIn;

    /**
     * @notice The Aave receipt token address.
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
     * @notice The Aave Lending Pool contract.
     */
    IPool public lendingPool;

    /**
     * @notice The Aave Rewards Controller contract.
     */
    IRewardsController public rewardsController;

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
     * @notice Initializes the Aave Strategy contract with necessary parameters.
     *
     * @dev Configures core components such as manager, tokens, pools, and reward systems
     * needed for the strategy to operate.
     *
     * @dev This function is only callable once due to the `initializer` modifier.
     *
     * @notice Ensures that critical addresses are non-zero to prevent misconfiguration:
     * - `_params.manager` must be valid (`"3065"` error code if invalid).
     * - `_params.lendingPool` must be valid (`"3036"` error code if invalid).
     * - `_params.rewardsController` must be valid (`"3036"` error code if invalid).
     * - `_params.tokenIn` and `_params.tokenOut` must be valid (`"3000"` error code if invalid).
     *
     * @param _params Struct containing all initialization parameters.
     */
    function initialize(
        InitializerParams memory _params
    ) public initializer {
        require(_params.manager != address(0), "3065");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");
        require(_params.lendingPool != address(0), "3036");
        require(_params.rewardsController != address(0), "3039");

        __StrategyBase_init({ _initialOwner: _params.owner });

        manager = IManager(_params.manager);
        rewardToken = _params.rewardToken;
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();
        lendingPool = IPool(_params.lendingPool);
        rewardsController = IRewardsController(_params.rewardsController);

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: manager.receiptTokenFactory(),
                _receiptTokenName: "Aave Strategy Receipt Token",
                _receiptTokenSymbol: "AaRT"
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
    ) external override nonReentrant onlyValidAmount(_amount) onlyStrategyManager returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");
        uint256 balanceBefore = IAToken(tokenOut).scaledBalanceOf(_recipient);
        uint16 refCode = _data.length > 0 ? abi.decode(_data, (uint16)) : 0;

        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });

        // Supply to the Aave Lending Pool on behalf of the `_recipient`.
        IERC20(_asset).forceApprove({ spender: address(lendingPool), value: _amount });
        lendingPool.supply({ asset: _asset, amount: _amount, onBehalfOf: _recipient, referralCode: refCode });

        uint256 shares = IAToken(tokenOut).scaledBalanceOf(_recipient) - balanceBefore;
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
     * @param _shares The amount to withdraw.
     * @param _recipient The address of the recipient.
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
        require(_shares <= recipients[_recipient].totalShares, "2002");

        WithdrawParams memory params = WithdrawParams({
            shares: _shares,
            totalShares: recipients[_recipient].totalShares,
            shareRatio: 0,
            shareDecimals: sharesDecimals,
            investment: 0,
            assetsToWithdraw: 0,
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

        // Since Aave generates yield in the same token as the tokenOut, we must calculate the amount of tokenOut
        // (including both the initial deposit and accrued yield) to be withdrawn. To achieve this, we apply the
        // percentage of the user's total shares to be withdrawn relative to their entire shareholding to the available
        // balance of aTokens in the Aave pool, ensuring the correct proportion of assets is withdrawn.
        // Note: In case that params.shareRatio is equal to 1 (100% of shares are being withdrawn),
        // params.assetsToWithdraw should be set to type(uint256).max as then we are sure that we will withdraw all
        // remaining balance from given aToken, and totalShares will be zeroed.
        params.assetsToWithdraw = params.shareRatio == 10 ** params.shareDecimals
            ? type(uint256).max
            : IAToken(tokenOut).balanceOf(_recipient) * params.shareRatio / 10 ** params.shareDecimals;

        // To accurately compute the protocol's fees from the yield generated by the strategy, we first need to
        // determine the percentage of the initial investment being withdrawn. This allows us to assess whether any
        // yield has been generated beyond the initial investment.
        params.investment = (recipients[_recipient].investedAmount * params.shareRatio) / (10 ** params.shareDecimals);

        // Perform the withdrawal operation from user's holding address.
        // Note: The `withdraw` function can be paused by Aave protocol, reverting the transaction.
        params.balanceBefore = IERC20(tokenIn).balanceOf(_recipient);
        _genericCall({
            _holding: _recipient,
            _contract: address(lendingPool),
            _call: abi.encodeCall(IPool.withdraw, (_asset, params.assetsToWithdraw, _recipient))
        });

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
     * @notice Claims rewards from the Aave lending pool.
     *
     * @param _recipient The address on behalf of which the rewards are claimed.
     *
     * @return The amounts of rewards claimed.
     * @return The addresses of the reward tokens.
     */
    function claimRewards(
        address _recipient,
        bytes calldata
    ) external override nonReentrant onlyStrategyManager returns (uint256[] memory, address[] memory) {
        // aTokens should be checked for rewards eligibility.
        address[] memory eligibleTokens = new address[](1);
        eligibleTokens[0] = tokenOut;

        // Make the claimAllRewards through the user's Holding.
        (, bytes memory returnData) = _genericCall({
            _holding: _recipient,
            _contract: address(rewardsController),
            _call: abi.encodeCall(IRewardsController.claimAllRewards, (eligibleTokens, _recipient))
        });

        // Assert the call succeeded.
        (address[] memory rewardsList, uint256[] memory claimedAmounts) = abi.decode(returnData, (address[], uint256[]));

        // Return if no rewards were claimed.
        if (rewardsList.length == 0) return (claimedAmounts, rewardsList);

        (uint256 performanceFee,,) = _getStrategyManager().strategyInfo(address(this));
        address feeAddr = manager.feeAddress();

        // Take performance fee for all the rewards.
        for (uint256 i = 0; i < rewardsList.length; i++) {
            uint256 fee = OperationsLib.getFeeAbsolute(claimedAmounts[i], performanceFee);
            if (fee > 0) {
                claimedAmounts[i] -= fee;
                emit FeeTaken(rewardsList[i], feeAddr, fee);
                IHolding(_recipient).transfer({ _token: rewardsList[i], _to: feeAddr, _amount: fee });
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
