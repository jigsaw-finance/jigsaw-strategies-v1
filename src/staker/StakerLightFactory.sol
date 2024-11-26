// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { IStakerLight } from "./interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "./interfaces/IStakerLightFactory.sol";

/**
 * @title StakerLightFactory
 * @dev This contract is used to create new instances of StakerLight contract for strategies using the clone factory  pattern.
 */
contract StakerLightFactory is IStakerLightFactory, Ownable2Step {
    /**
     * @notice Address of the reference implementation of the StakerLight contract.
     */
    address public referenceImplementation;

    // -- Constructor --

    /**
     * @notice Creates a new StakerLightFactory contract.
     * @param _initialOwner The initial owner of the contract.
     * @param _referenceImplementation The StakerLight reference implementation for used for cloning.
     */
    constructor(address _initialOwner, address _referenceImplementation) Ownable(_initialOwner) {
        // Assert that referenceImplementation has code in it to protect the system from cloning invalid implementation.
        require(_referenceImplementation.code.length > 0, "Reference implementation has no code");

        emit StakerLightImplementationUpdated(_referenceImplementation);
        referenceImplementation = _referenceImplementation;
    }

    // -- Administration --

    /**
     * @notice Sets the reference implementation address for the StakerLight contract.
     * @param _referenceImplementation Address of the new reference implementation contract.
     */
    function setStakerLightReferenceImplementation(
        address _referenceImplementation
    ) external override onlyOwner {
        // Assert that referenceImplementation has code in it to protect the system from cloning invalid implementation.
        require(_referenceImplementation.code.length > 0, "Reference implementation has no code");

        emit StakerLightImplementationUpdated(_referenceImplementation);
        referenceImplementation = _referenceImplementation;
    }

    // -- StakerLight contract creation --

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
    ) external override returns (address newStakerLightAddress) {
        // Clone the StakerLight contract implementation for the new StakerLight contract.
        newStakerLightAddress = Clones.cloneDeterministic({
            implementation: referenceImplementation,
            salt: bytes32(uint256(uint160(msg.sender)))
        });

        // Emit the event indicating the successful StakerLight contract creation.
        emit StakerLightCreated({ newStakerLightAddress: newStakerLightAddress, creator: msg.sender });

        // Initialize the new StakerLight contract's contract.
        IStakerLight(newStakerLightAddress).initialize({
            _initialOwner: _initialOwner,
            _holdingManager: _holdingManager,
            _rewardToken: _rewardToken,
            _strategy: _strategy,
            _rewardsDuration: _rewardsDuration
        });
    }

    /**
     * @dev Renounce ownership override to avoid losing contract's ownership.
     */
    function renounceOwnership() public pure virtual override {
        revert("1000");
    }
}
