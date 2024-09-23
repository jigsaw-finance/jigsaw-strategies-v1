// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPool } from "@aave/v3-core/interfaces/IPool.sol";
import { IRewardsController } from "@aave/v3-periphery/rewards/interfaces/IRewardsController.sol";

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
 * @title AaveV3Strategy
 * @dev Strategy used for Aave lending pool.
 * @author Hovooo (@hovooo)
 */
contract AaveV3Strategy is IStrategy, StrategyBaseUpgradeable {
    using SafeERC20 for IERC20;

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     */
    struct InitializerParams {
        address owner; // The address of the initial owner of the Strategy contract
        address managerContainer; // The address of the contract that contains the manager contract
        address stakerFactory; // The address of the StakerLightFactory contract
        address lendingPool; // The address of the Aave Lending Pool
        address rewardsController; // The address of the Aave Rewards Controller
        address rewardToken; // The address of the Aave reward token associated with the strategy
        address jigsawRewardToken; // The address of the Jigsaw reward token associated with the strategy
        uint256 jigsawRewardDuration; // The address of the initial Jigsaw reward distribution duration for the strategy
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of the Aave receipt token (aToken)
    }

    // -- Events --

    /**
     * @notice Emitted when the Rewards Controller address is updated.
     * @param _old The old Rewards Controller address.
     * @param _new The new Rewards Controller address.
     */
    event RewardsControllerUpdated(address indexed _old, address indexed _new);

    /**
     * @notice Emitted when a performance fee is taken.
     * @param token The token from which the fee is taken.
     * @param feeAddress The address that receives the fee.
     * @param amount The amount of the fee.
     */
    event FeeTaken(address indexed token, address indexed feeAddress, uint256 amount);

    /**
     * @notice Emitted when the Lending Pool address is updated.
     * @param _old The old Lending Pool address.
     * @param _new The new Lending Pool address.
     */
    event LendingPoolUpdated(address indexed _old, address indexed _new);

    /**
     * @notice Emitted when the Reward Token address is updated.
     * @param _old The old Reward Token address.
     * @param _new The new Reward Token address.
     */
    event RewardTokenUpdated(address indexed _old, address indexed _new);

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
     * @notice The total investments in the strategy.
     */
    uint256 public totalInvestments;

    /**
     * @notice A mapping that stores participant details by address.
     */
    mapping(address => IStrategy.RecipientInfo) public override recipients;

    /**
     * @notice Storage gap to reserve storage slots in a base contract, to allow future versions of
     * StrategyBaseUpgradeable to use up those slots without affecting the storage layout of child contracts.
     */
    uint256[49] __gap;

    // -- Constructor --

    constructor() {
        _disableInitializers();
    }

    // -- Initialization --

    /**
     * @notice Initializer for the Aave Strategy.
     */
    function initialize(InitializerParams memory _params) public initializer {
        require(_params.managerContainer != address(0), "3065");
        require(_params.lendingPool != address(0), "3036");
        require(_params.rewardsController != address(0), "3039");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        managerContainer = IManagerContainer(_params.managerContainer);
        rewardsController = IRewardsController(_params.rewardsController);
        rewardToken = _params.rewardToken;
        lendingPool = IPool(_params.lendingPool);
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _receiptTokenFactory: _getManager().receiptTokenFactory(),
                _receiptTokenName: "Aave Strategy Receipt Token",
                _receiptTokenSymbol: "AaRT"
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
    ) external override onlyValidAmount(_amount) onlyStrategyManager nonReentrant returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");

        uint16 refCode = 0;
        if (_data.length > 0) {
            refCode = abi.decode(_data, (uint16));
        }

        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_recipient);
        OperationsLib.safeApprove({ token: _asset, to: address(lendingPool), value: _amount });
        lendingPool.supply({ asset: _asset, amount: _amount, onBehalfOf: _recipient, referralCode: refCode });
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(_recipient);

        recipients[_recipient].investedAmount += _amount;
        recipients[_recipient].totalShares += balanceAfter - balanceBefore;
        totalInvestments += _amount;

        _mint({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _amount: balanceAfter - balanceBefore,
            _tokenDecimals: IERC20Metadata(tokenOut).decimals()
        });

        jigsawStaker.deposit({ _user: _recipient, _amount: recipients[_recipient].investedAmount });

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

        uint256 shareRatio = OperationsLib.getRatio({
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

        uint256 investment =
            (recipients[_recipient].investedAmount * shareRatio) / (10 ** IERC20Metadata(tokenOut).decimals());

        IHolding(_recipient).transfer({ _token: tokenOut, _to: address(this), _amount: _shares });

        uint256 balanceBefore = IERC20(tokenIn).balanceOf(_recipient);
        lendingPool.withdraw({ asset: _asset, amount: _shares, to: _recipient });
        uint256 balanceAfter = IERC20(tokenIn).balanceOf(_recipient);

        _extractTokenInRewards({
            _ratio: shareRatio,
            _result: balanceAfter - balanceBefore,
            _recipient: _recipient,
            _decimals: IERC20Metadata(tokenOut).decimals()
        });

        jigsawStaker.withdraw({ _user: _recipient, _amount: recipients[_recipient].investedAmount });

        recipients[_recipient].totalShares =
            _shares > recipients[_recipient].totalShares ? 0 : recipients[_recipient].totalShares - _shares;
        recipients[_recipient].investedAmount =
            investment > recipients[_recipient].investedAmount ? 0 : recipients[_recipient].investedAmount - investment;
        totalInvestments = balanceAfter - balanceBefore > totalInvestments ? 0 : totalInvestments - investment;

        emit Withdraw({ asset: _asset, recipient: _recipient, shares: _shares, amount: balanceAfter - balanceBefore });
        return (balanceAfter - balanceBefore, investment);
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
    ) external override onlyStrategyManager nonReentrant returns (uint256[] memory, address[] memory) {
        // aTokens should be checked for rewards eligibility.
        address[] memory eligibleTokens = new address[](1);
        eligibleTokens[0] = tokenOut;

        // Make the claimAllRewards through the user's Holding.
        (bool success, bytes memory returnData) = IHolding(_recipient).genericCall({
            _contract: address(rewardsController),
            _call: abi.encodeWithSignature(
                "claimAllRewards(address[],address)",
                eligibleTokens, // List of assets to check eligible distributions before claiming rewards
                _recipient // The address that will be receiving the rewards
            )
        });

        // Assert the call succeeded.
        require(success, OperationsLib.getRevertMsg(returnData));
        (address[] memory rewardsList, uint256[] memory claimedAmounts) = abi.decode(returnData, (address[], uint256[]));

        // Return if no rewards were claimed.
        if (rewardsList.length == 0) return (claimedAmounts, rewardsList);

        (uint256 performanceFee,,) = _getStrategyManager().strategyInfo(address(this));
        address feeAddr = _getManager().feeAddress();

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
        (uint256 performanceFee,,) = _getStrategyManager().strategyInfo(address(this));
        if (performanceFee == 0) return;

        if (_ratio > (10 ** _decimals) && _result < recipients[_recipient].investedAmount) return;
        uint256 rewardAmount = 0;
        if (_ratio >= (10 ** _decimals)) rewardAmount = _result - recipients[_recipient].investedAmount;
        if (rewardAmount == 0) return;

        uint256 fee = OperationsLib.getFeeAbsolute(rewardAmount, performanceFee);

        if (fee > 0) {
            address feeAddr = _getManager().feeAddress();
            emit FeeTaken(tokenIn, feeAddr, fee);
            IHolding(_recipient).transfer(tokenIn, feeAddr, fee);
        }
    }
}
