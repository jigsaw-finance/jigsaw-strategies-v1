// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title JigsawPoints
 * @notice Implementation of the Jigsaw Points ERC20 token.
 *
 * @dev This contract inherits functionalities from  `ERC20`, `ERC20Burnable`, `AccessControlDefaultAdminRules`,
 * and `ERC20Permit`.
 *
 * @author Hovooo (@hovooo)
 *
 * @custom:security-contact support@jigsaw.finance
 */
contract JigsawPoints is ERC20, ERC20Burnable, AccessControlDefaultAdminRules, ERC20Permit {
    /**
     * @notice Role allowed to perform `burnFrom` operation.
     */
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // --- Errors ---
    /**
     * @notice The operation failed because renouncing `DEFAULT_ADMIN_ROLE` is prohibited.
     */
    error RenouncingDefaultAdminRoleProhibited();

    /**
     * @notice The operation failed because amount is zero.
     */
    error InvalidAmount();

    // -- Modifiers --

    /**
     * @notice Modifier to check that the amount is valid (non-zero).
     * @param _val The amount to check.
     */
    modifier validAmount(
        uint256 _val
    ) {
        if (_val == 0) revert InvalidAmount();
        _;
    }

    // -- Constructor --

    /**
     * @notice Constructor that initializes the contract with an `_initialAdmin` and `_premintAmount` amount.
     * @param _initialAdmin address of the initial admin.
     * @param _premintAmount amount of tokens to premint.
     */
    constructor(
        address _initialAdmin,
        uint256 _premintAmount
    )
        ERC20("Jigsaw Points", "jPoints")
        ERC20Permit("Jigsaw Points")
        AccessControlDefaultAdminRules(2 days, _initialAdmin)
    {
        _mint(_initialAdmin, _premintAmount * 10 ** decimals());
    }

    // --- Administration ---

    /**
     * @notice Creates a `value` amount of tokens and assigns them to `to`, by transferring it from address(0). Relies
     * on
     * the `_update` mechanism.
     *
     * @dev Emits a `Transfer` event with `from` set to the zero address.
     */
    function mint(address to, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burns token from an address.
     * @param _user to burn tokens from.
     * @param _amount of tokens to be burnt.
     */
    function burnFrom(address _user, uint256 _amount) public override onlyRole(BURNER_ROLE) validAmount(_amount) {
        _burn(_user, _amount);
    }

    /**
     * @notice Prevents the renouncement of the default admin role by overriding `beginDefaultAdminTransfer`.
     * @param newAdmin address.
     */
    function beginDefaultAdminTransfer(
        address newAdmin
    ) public override(AccessControlDefaultAdminRules) onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert RenouncingDefaultAdminRoleProhibited();
        _beginDefaultAdminTransfer(newAdmin);
    }
}
