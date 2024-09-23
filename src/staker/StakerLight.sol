// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IHoldingManager } from "@jigsaw/src/interfaces/core/IHoldingManager.sol";

import { IStakerLight } from "./interfaces/IStakerLight.sol";

/**
 * @title StakerLight
 * @notice StakerLight is a contract responsible for distributing Jigsaw rewards to Jigsaw strategy investors.
 * @notice This contract accepts Jigsaw Strategy's receipt tokens as `tokenIn` and distributes rewards accordingly.
 * @notice It is not intended for direct use; interaction should be done through the corresponding `Staker` contract.
 *
 * @dev This contract is called light due to the fact that it does not actually transfer the receipt tokens from the
 * user and is only used for accounting.
 * @dev This contract inherits functionalities from `Ownable2Step`, `Pausable`, and `ReentrancyGuard`.
 *
 * @author Hovooo (@hovooo)
 */
contract StakerLight is IStakerLight, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @notice Address of the HoldingManager Contract.
     */
    IHoldingManager public holdingManager;

    /**
     * @notice Address of the reward token.
     */
    address public override rewardToken;

    /**
     * @notice Address of the corresponding strategy.
     */
    address public override strategy;

    /**
     * @notice Timestamp indicating when the current reward distribution ends.
     */
    uint256 public override periodFinish = 0;

    /**
     * @notice Rate of rewards per second.
     */
    uint256 public override rewardRate = 0;

    /**
     * @notice Duration of current reward period.
     */
    uint256 public override rewardsDuration;

    /**
     * @notice Timestamp of the last update time.
     */
    uint256 public override lastUpdateTime;

    /**
     * @notice Stored rewards per token.
     */
    uint256 public override rewardPerTokenStored;

    /**
     * @notice Mapping of user addresses to the amount of rewards already paid to them.
     */
    mapping(address => uint256) public override userRewardPerTokenPaid;

    /**
     * @notice Mapping of user addresses to their accrued rewards.
     */
    mapping(address => uint256) public override rewards;

    /**
     * @notice Total supply limit of the staking token.
     */
    uint256 public constant totalSupplyLimit = 1e34;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    // --- Modifiers ---

    /**
     * @notice Modifier to update the reward for a specified account.
     * @param account The account for which the reward needs to be updated.
     */
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /**
     * @notice Modifier to check if the provided address is valid.
     * @param _address to be checked for validity.
     */
    modifier validAddress(address _address) {
        if (_address == address(0)) revert InvalidAddress();
        _;
    }

    /**
     * @notice Modifier to check if the provided amount is valid.
     * @param _amount to be checked for validity.
     */
    modifier validAmount(uint256 _amount) {
        if (_amount == 0) revert InvalidAmount();
        _;
    }

    /**
     * @notice Modifier to restrict a function to be called only by the staking manager.
     * @notice Reverts the transaction if the caller is not the staking manager.
     */
    modifier onlyStrategy() {
        if (msg.sender != strategy) revert UnauthorizedCaller();
        _;
    }

    /**
     * @notice Modifier to restrict a function to be called only by the Holding's owner.
     * @notice Reverts the transaction if the msg.sender is not the owner of the Holding.
     */
    modifier onlyInvestor(address _holding) {
        if (holdingManager.userHolding(msg.sender) != _holding) revert UnauthorizedCaller();
        _;
    }

    // --- Constructor ---

    constructor() {
        _disableInitializers();
    }

    // -- Initializer --

    /**
     * @notice Initializer for the Staker Light contract.
     *
     * @param _initialOwner The initial owner of the contract.
     * @param _holdingManager The address of the contract that contains the Holding manager contract.
     * @param _rewardToken The address of the reward token.
     * @param _strategy The address of the strategy contract.
     * @param _rewardsDuration The duration of the rewards period, in seconds.
     */
    function initialize(
        address _initialOwner,
        address _holdingManager,
        address _rewardToken,
        address _strategy,
        uint256 _rewardsDuration
    ) public initializer validAddress(_rewardToken) validAddress(_strategy) {
        __Ownable_init(_initialOwner);
        __Pausable_init();

        holdingManager = IHoldingManager(_holdingManager);
        rewardToken = _rewardToken;
        strategy = _strategy;
        rewardsDuration = _rewardsDuration;
        periodFinish = block.timestamp + rewardsDuration;
    }

    // -- Staker's operations  --

    /**
     * @notice Performs a deposit operation for `_user`.
     * @dev Updates participants' rewards.
     *
     * @param _user to deposit for.
     * @param _amount to deposit.
     */
    function deposit(
        address _user,
        uint256 _amount
    ) external override onlyStrategy whenNotPaused nonReentrant updateReward(_user) validAmount(_amount) {
        // Ensure that deposit operation will never surpass supply limit
        if (_totalSupply + _amount > totalSupplyLimit) revert DepositSurpassesSupplyLimit(_amount, totalSupplyLimit);
        _totalSupply += _amount;

        _balances[_user] += _amount;
        emit Staked(_user, _amount);
    }

    /**
     * @notice Withdraws investment from staking.
     * @dev Updates participants' rewards.
     *
     * @param _user to withdraw for.
     * @param _amount to withdraw.
     */
    function withdraw(
        address _user,
        uint256 _amount
    ) external override onlyStrategy whenNotPaused nonReentrant updateReward(_user) validAmount(_amount) {
        _totalSupply -= _amount;
        _balances[_user] = _balances[_user] - _amount;
        emit Withdrawn(_user, _amount);
    }

    /**
     * @notice Claims the rewards for the caller.
     * @dev This function allows the caller to claim their earned rewards.
     *
     * @param _holding to claim rewards for.
     * @param _to address to which rewards will be sent.
     */
    function claimRewards(
        address _holding,
        address _to
    ) external override whenNotPaused nonReentrant onlyInvestor(_holding) updateReward(_holding) {
        uint256 reward = rewards[_holding];
        if (reward == 0) revert NothingToClaim();

        rewards[_holding] = 0;
        emit RewardPaid(_holding, reward);
        IERC20(rewardToken).safeTransfer(_to, reward);
    }

    // -- Administration --

    /**
     * @notice Sets the duration of each reward period.
     * @param _rewardsDuration The new rewards duration.
     */
    function setRewardsDuration(uint256 _rewardsDuration) external override onlyOwner {
        if (block.timestamp <= periodFinish) revert PreviousPeriodNotFinished(block.timestamp, periodFinish);
        emit RewardsDurationUpdated(rewardsDuration, _rewardsDuration);
        rewardsDuration = _rewardsDuration;
    }

    /**
     * @notice Adds more rewards to the contract.
     *
     * @dev Prior approval is required for this contract to transfer rewards from `_from` address.
     *
     * @param _from address to transfer rewards from.
     * @param _amount The amount of new rewards.
     */
    function addRewards(
        address _from,
        uint256 _amount
    ) external override onlyOwner validAmount(_amount) updateReward(address(0)) {
        // Transfer assets from the user's wallet to this contract.
        IERC20(rewardToken).safeTransferFrom({ from: _from, to: address(this), value: _amount });

        uint256 duration = rewardsDuration;
        if (duration == 0) revert ZeroRewardsDuration();
        if (block.timestamp >= periodFinish) {
            rewardRate = _amount / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (_amount + leftover) / duration;
        }

        if (rewardRate == 0) revert RewardAmountTooSmall();

        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        if (rewardRate > (balance / duration)) revert RewardRateTooBig();

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(_amount);
    }

    /**
     * @notice Triggers stopped state.
     */
    function pause() external override onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Returns to normal state.
     */
    function unpause() external override onlyOwner whenPaused {
        _unpause();
    }

    /**
     * @notice Renounce ownership override to prevent accidental loss of contract ownership.
     * @dev This function ensures that the contract's ownership cannot be lost unintentionally.
     */
    function renounceOwnership() public pure override {
        revert RenouncingOwnershipProhibited();
    }

    // -- Getters --

    /**
     * @notice Returns the total supply of the staking token.
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice Returns the total invested amount for an account.
     * @param _account The participant's address.
     */
    function balanceOf(address _account) external view override returns (uint256) {
        return _balances[_account];
    }

    /**
     * @notice Returns the last time rewards were applicable.
     */
    function lastTimeRewardApplicable() public view override returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @notice Returns rewards per token.
     */
    function rewardPerToken() public view override returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / _totalSupply);
    }

    /**
     * @notice Returns accrued rewards for an account.
     * @param _account The participant's address.
     */
    function earned(address _account) public view override returns (uint256) {
        return
            ((_balances[_account] * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18) + rewards[_account];
    }

    /**
     * @notice Returns the reward amount for a specific time range.
     */
    function getRewardForDuration() external view override returns (uint256) {
        return rewardRate * rewardsDuration;
    }
}
