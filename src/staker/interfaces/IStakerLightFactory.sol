// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IStakerLightFactory {
    /**
     * @notice Emitted when StakerLight reference implementation is updated.
     *
     * @param newStakerLightImplementationAddress Address of the newly created StakerLight contract.
     */
    event StakerLightImplementationUpdated(address indexed newStakerLightImplementationAddress);

    /**
     * @notice Emitted when a new StakerLight contract is created.
     *
     * @param newStakerLightAddress Address of the newly created StakerLight contract.
     * @param creator Address of the account that initiated the creation.
     */
    event StakerLightCreated(address indexed newStakerLightAddress, address indexed creator);

    /**
     * @notice Sets the reference implementation address for the StakerLight contract.
     * @param _referenceImplementation Address of the new reference implementation contract.
     */
    function setStakerLightReferenceImplementation(
        address _referenceImplementation
    ) external;

    /**
     * @notice Creates a new StakerLight contract by cloning the reference implementation.
     *
     * @param _initialOwner The initial owner of the StakerLight contract
     * @param _holdingManager The address of the contract that contains the Holding manager contract.
     * @param _rewardToken The address of the reward token
     * @param _strategy The address of the strategy contract
     * @param _rewardsDuration The duration of the rewards period, in seconds
     *
     * @return newStakerLightAddress Address of the newly created StakerLight contract.
     */
    function createStakerLight(
        address _initialOwner,
        address _holdingManager,
        address _rewardToken,
        address _strategy,
        uint256 _rewardsDuration
    ) external returns (address);
}
