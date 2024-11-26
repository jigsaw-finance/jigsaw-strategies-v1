// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/// @title Interface for Staker contract
interface IStakerLight {
    // --- Errors ---
    /**
     * @notice The operation failed because provided address is invalid.
     */
    error InvalidAddress();

    /**
     * @notice The operation failed because provided amount is invalid.
     */
    error InvalidAmount();

    /**
     * @notice The operation failed because caller was unauthorized for the action.
     */
    error UnauthorizedCaller();

    /**
     * @notice The operation failed because the previous rewards period must end first.
     * @param timestamp The current timestamp when the error occurred.
     * @param periodFinish The timestamp when the current rewards period is expected to end.
     */
    error PreviousPeriodNotFinished(uint256 timestamp, uint256 periodFinish);

    /**
     * @notice The operation failed because rewards duration is zero.
     */
    error ZeroRewardsDuration();

    /**
     * @notice The operation failed because reward rate was zero.
     * Caused by an insufficient amount of rewards provided.
     */
    error RewardAmountTooSmall();

    /**
     * @notice The operation failed because reward rate is too big.
     */
    error RewardRateTooBig();

    /**
     * @notice The operation failed because there were no rewards to distribute.
     */
    error NoRewardsToDistribute();

    /**
     * @notice The operation failed because deposit surpasses the supply limit.
     * @param _amount of tokens attempting to be deposited.
     * @param supplyLimit allowed for deposits.
     */
    error DepositSurpassesSupplyLimit(uint256 _amount, uint256 supplyLimit);

    /**
     * @notice The operation failed because user doesn't have rewards to claim.
     */
    error NothingToClaim();

    /**
     * @notice The operation failed because renouncing ownership is prohibited.
     */
    error RenouncingOwnershipProhibited();

    // --- Events ---

    /**
     * @notice Event emitted when the rewards duration is updated.
     * @param oldDuration The previous rewards duration.
     * @param newDuration The new rewards duration.
     */
    event RewardsDurationUpdated(uint256 indexed oldDuration, uint256 indexed newDuration);

    /**
     * @notice Event emitted when new rewards are added.
     * @param reward The amount of rewards added.
     */
    event RewardAdded(uint256 indexed reward);

    /**
     * @notice Event emitted when a participant deposits an amount.
     * @param user The address of the participant who made the deposit.
     * @param amount The amount that was deposited.
     */
    event Staked(address indexed user, uint256 indexed amount);

    /**
     * @notice Event emitted when a participant withdraws their stake.
     * @param user The address of the participant who withdrew their stake.
     * @param amount The amount that was withdrawn.
     */
    event Withdrawn(address indexed user, uint256 indexed amount);

    /**
     * @notice Event emitted when a participant claims their rewards.
     * @param user The address of the participant who claimed the rewards.
     * @param reward The amount of rewards that were claimed.
     */
    event RewardPaid(address indexed user, uint256 indexed reward);

    /**
     * @notice Event emitted when a ERC20 is recovered.
     * @param token The address of the recovered token.
     * @param amount The amount of the recovered token.
     */
    event Recovered(address token, uint256 amount);

    /**
     * @notice returns reward token address.
     */
    function rewardToken() external view returns (address);

    /**
     * @notice returns address of the corresponding strategy.
     */
    function strategy() external view returns (address);

    /**
     * @notice when current contract distribution ends (block timestamp + rewards duration).
     */
    function periodFinish() external view returns (uint256);

    /**
     * @notice rewards per second.
     */
    function rewardRate() external view returns (uint256);

    /**
     * @notice reward period.
     */
    function rewardsDuration() external view returns (uint256);

    /**
     * @notice last reward update timestamp.
     */
    function lastUpdateTime() external view returns (uint256);

    /**
     * @notice reward-token share.
     */
    function rewardPerTokenStored() external view returns (uint256);

    /**
     * @notice rewards paid to participants so far.
     */
    function userRewardPerTokenPaid(
        address participant
    ) external view returns (uint256);

    /**
     * @notice accrued rewards per participant.
     */
    function rewards(
        address participant
    ) external view returns (uint256);

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
    ) external;

    /**
     * @notice sets the new rewards duration.
     */
    function setRewardsDuration(
        uint256 _rewardsDuration
    ) external;

    /**
     * @notice Adds more rewards to the contract.
     *
     * @dev Prior approval is required for this contract to transfer rewards from `owner`'s address.
     *
     * @param _amount The amount of new rewards.
     */
    function addRewards(
        uint256 _amount
    ) external;

    /**
     * This function allows the contract owner to recover ERC20 tokens that might have been
     * accidentally or otherwise left within the contract. It requires the caller to have the
     * `onlyOwner` modifier, ensuring that only the owner of the contract can invoke it.
     *
     * @param tokenAddress The contract address of the ERC20 token to be recovered.
     * @param tokenAmount The amount of the specified ERC20 token to be transferred to the owner.
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    /**
     * @notice returns the total tokenIn supply.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice returns total invested amount for an account.
     * @param _account participant address
     */
    function balanceOf(
        address _account
    ) external view returns (uint256);

    /**
     * @notice returns the last time rewards were applicable.
     */
    function lastTimeRewardApplicable() external view returns (uint256);

    /**
     * @notice returns rewards per tokenIn.
     */
    function rewardPerToken() external view returns (uint256);

    /**
     * @notice rewards accrued rewards for account.
     *  @param _account participant's address
     */
    function earned(
        address _account
    ) external view returns (uint256);

    /**
     * @notice returns reward amount for a specific time range.
     */
    function getRewardForDuration() external view returns (uint256);

    /**
     * @notice Performs a deposit operation for `_user`.
     * @dev Updates participants' rewards.
     *
     * @param _user to deposit for.
     * @param _amount to deposit.
     */
    function deposit(address _user, uint256 _amount) external;

    /**
     * @notice Withdraws investment from staking.
     * @dev Updates participants' rewards.
     *
     * @param _user to withdraw for.
     * @param _amount to withdraw.
     */
    function withdraw(address _user, uint256 _amount) external;

    /**
     * @notice Claims the rewards for the caller.
     * @dev This function allows the caller to claim their earned rewards.
     *
     * @param _holding to claim rewards for.
     * @param _to address to which rewards will be sent.
     */
    function claimRewards(address _holding, address _to) external;
}
