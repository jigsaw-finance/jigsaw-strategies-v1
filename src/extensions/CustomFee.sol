// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @title CustomFee Contract used for custom fee functionality through Jigsaw Strategies .
 * @author Hovooo (@hovooo)
 */
contract CustomFee is Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    /**
     * @notice Emitted when the default fee is updated.
     * @param oldFee The previous fee.
     * @param newFee The new fee.
     */
    event CustomPerformanceFeeUpdated(uint256 indexed oldFee, uint256 indexed newFee);

    /**
     * @notice Returns the maximum custom performance fee.
     * @dev Uses 2 decimal precision, where 1% is represented as 100.
     */
    uint256 public immutable MAX_CUSTOM_PERFORMANCE_FEE = 2500; //25%

    /**
     * @notice Returns customFee associated with the holding.
     */
    mapping(address recipient => uint256 customFee) public recipientCustomFee;

    /**
     * @notice Initializes the CustomFee contract.
     * @param _initialOwner The address of the initial owner of the contract.
     */
    function __CustomFee_init(
        address _initialOwner
    ) internal onlyInitializing {
        __Ownable_init(_initialOwner);
        __Ownable2Step_init();
        __ReentrancyGuard_init();
    }

    /**
     * @notice Sets a custom fee for a specific holding.
     * @dev Only the owner of the contract is authorized to perform upgrades, ensuring that only authorized parties
     * @param _recipient The address of the holding.
     * @param _val The custom fee to set.
     */
    function setRecipientCustomFee(address _recipient, uint256 _val) external onlyOwner onlyValidAddress(_recipient) {
        require(recipientCustomFee[_recipient] != _val, "3017");
        require(_val < MAX_CUSTOM_PERFORMANCE_FEE, "3018");
        emit CustomPerformanceFeeUpdated(recipientCustomFee[_recipient], _val);
        recipientCustomFee[_recipient] = _val;
    }

    /**
     * @notice Ensures that the provided address is valid (not the zero address).
     * @dev Reverts with "3000" if the address is the zero address.
     * @param _addr The address to validate.
     */
    modifier onlyValidAddress(
        address _addr
    ) {
        require(_addr != address(0), "3000");
        _;
    }
}