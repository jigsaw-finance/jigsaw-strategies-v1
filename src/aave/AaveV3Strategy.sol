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
     * @notice Temporary data structure used during the claim rewards process.
     * @dev This struct holds intermediate variables required for calculating rewards and managing fees.
     */
    struct ClaimRewardsTempData {
        uint256[] rewardsResult; // Array that holds the amounts of rewards claimed.
        address[] rewardTokensResult; // Array that holds the addresses of the reward tokens.
        uint256 fee; // The performance fee deducted from the rewards.
        uint256 amount; // The net amount of rewards after deducting the performance fee.
        bytes returnData; // The data returned from external contract calls, used for validation and debugging.
        bool success; // Flag indicating whether the external call to claim rewards was successful.
        uint256 rewardsBalanceBefore; // The balance of rewards tokens before the claim operation.
        uint256 rewardsBalanceAfter; // The balance of rewards tokens after the claim operation.
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
     * @notice Initializer for the Aave Strategy.
     *
     * @param _managerContainer The address of the contract that contains the manager contract.
     * @param _lendingPool The address of the Aave Lending Pool.
     * @param _rewardsController The address of the Aave Rewards Controller.
     * @param _tokenIn The address of the LP token.
     * @param _tokenOut The address of the Aave receipt token (aToken).
     * @param _receiptTokenName The name of the receipt token.
     * @param _receiptTokenSymbol The symbol of the receipt token.
     */
    function initialize(
        address _owner,
        address _managerContainer,
        address _lendingPool,
        address _rewardsController,
        address _rewardToken,
        address _tokenIn,
        address _tokenOut,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) public initializer {
        require(_managerContainer != address(0), "3065");
        require(_lendingPool != address(0), "3036");
        require(_rewardsController != address(0), "3039");
        require(_tokenIn != address(0), "3000");
        require(_tokenOut != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _owner });

        managerContainer = IManagerContainer(_managerContainer);
        rewardsController = IRewardsController(_rewardsController);
        rewardToken = _rewardToken;
        lendingPool = IPool(_lendingPool);
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
        sharesDecimals = IERC20Metadata(_tokenOut).decimals();
        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _receiptTokenFactory: _getManager().receiptTokenFactory(),
                _receiptTokenName: _receiptTokenName,
                _receiptTokenSymbol: _receiptTokenSymbol
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

        recipients[_recipient].totalShares =
            _shares > recipients[_recipient].totalShares ? 0 : recipients[_recipient].totalShares - _shares;
        recipients[_recipient].investedAmount =
            investment > recipients[_recipient].investedAmount ? 0 : recipients[_recipient].investedAmount - investment;
        totalInvestments = balanceAfter - balanceBefore > totalInvestments ? 0 : totalInvestments - investment;

        emit Withdraw({ asset: _asset, recipient: _recipient, shares: _shares, amount: balanceAfter - balanceBefore });
        return (balanceAfter - balanceBefore, investment);
    }

    /**
     * @notice Claims rewards from the strategy.
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
        ClaimRewardsTempData memory tempData = ClaimRewardsTempData({
            rewardsResult: new uint256[](1),
            rewardTokensResult: new address[](1),
            fee: 0,
            amount: 0,
            returnData: "",
            success: false,
            rewardsBalanceBefore: 0,
            rewardsBalanceAfter: 0
        });

        tempData.rewardTokensResult[0] = rewardToken;
        address[] memory tokens = new address[](1);
        tokens[0] = tokenOut;

        tempData.rewardsBalanceBefore = IERC20(tempData.rewardTokensResult[0]).balanceOf(_recipient);

        (tempData.success, tempData.returnData) = IHolding(_recipient).genericCall({
            _contract: address(rewardsController),
            _call: abi.encodeWithSignature(
                "claimRewards(address[],uint256,address)",
                tokens,
                type(uint256).max,
                _recipient,
                tempData.rewardTokensResult[0]
                )
        });
        require(tempData.success, OperationsLib.getRevertMsg(tempData.returnData));
        tempData.rewardsBalanceAfter = IERC20(tempData.rewardTokensResult[0]).balanceOf(_recipient);
        tempData.amount = tempData.rewardsBalanceAfter - tempData.rewardsBalanceBefore;

        (uint256 performanceFee,,) = _getStrategyManager().strategyInfo(address(this));
        tempData.fee = OperationsLib.getFeeAbsolute(tempData.amount, performanceFee);

        if (tempData.fee > 0) {
            tempData.amount -= tempData.fee;
            address feeAddr = _getManager().feeAddress();
            emit FeeTaken(tempData.rewardTokensResult[0], feeAddr, tempData.fee);
            IHolding(_recipient).transfer({ _token: tempData.rewardTokensResult[0], _to: feeAddr, _amount: tempData.fee });
        }

        emit Rewards({
            recipient: _recipient,
            rewards: tempData.rewardsResult,
            rewardTokens: tempData.rewardTokensResult
        });

        tempData.rewardsResult[0] = tempData.amount;
        return (tempData.rewardsResult, tempData.rewardTokensResult);
    }

    // -- Administration --

    /**
     * @notice Sets a new Rewards Controller address.
     * @param _newAddr The new Rewards Controller address.
     */
    function setRewardsController(
        address _newAddr,
        address _rewardToken
    ) external onlyValidAddress(_newAddr) onlyOwner {
        emit RewardsControllerUpdated({ _old: address(rewardsController), _new: _newAddr });
        rewardsController = IRewardsController(_newAddr);
        rewardToken = _rewardToken;
    }

    // -- Getters --

    /**
     * @notice Not implemented.
     */
    function getRewards(address _recipient) external view override onlyValidAddress(_recipient) returns (uint256) {
        revert("Not Implemented");
    }

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
}
