// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IManagerContainer } from "@jigsaw/src/interfaces/core/IManagerContainer.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";
import { IStrategyManager } from "@jigsaw/src/interfaces/core/IStrategyManager.sol";

/**
 * @title StrategyBase Contract used for common functionality through Jigsaw Strategies .
 * @author Hovooo (@hovooo)
 */
abstract contract StrategyBaseUpgradeable is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @notice Emitted when a new underlying is added to the whitelist.
     */
    event UnderlyingAdded(address indexed newAddress);

    /**
     * @notice Emitted when a new underlying is removed from the whitelist.
     */
    event UnderlyingRemoved(address indexed old);

    /**
     * @notice Emitted when the address is updated.
     */
    event StrategyManagerUpdated(address indexed old, address indexed newAddress);

    /**
     * @notice Emitted when funds are saved in case of an emergency.
     */
    event SavedFunds(address indexed token, uint256 amount);

    /**
     * @notice Emitted when receipt tokens are minted.
     */
    event ReceiptTokensMinted(address indexed receipt, uint256 amount);

    /**
     * @notice Emitted when receipt tokens are burned.
     */
    event ReceiptTokensBurned(address indexed receipt, uint256 amount);

    /**
     * @notice Contract that contains the address of the manager contract.
     */
    IManagerContainer public managerContainer;

    /**
     * @notice Storage gap to reserve storage slots in a base contract, to allow future versions of
     * StrategyBaseUpgradeable to use up those slots without affecting the storage layout of child contracts.
     */
    uint256[49] __gap;

    /**
     * @notice Initializes the StrategyBase contract.
     * @param _initialOwner The address of the initial owner of the contract.
     */
    function __StrategyBase_init(
        address _initialOwner
    ) internal onlyInitializing {
        __Ownable_init(_initialOwner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Ensures that the caller is authorized to upgrade the contract.
     * @dev This function is called by the `upgradeToAndCall` function as part of the UUPS upgrade process.
     * Only the owner of the contract is authorized to perform upgrades, ensuring that only authorized parties
     * can modify the contract's logic.
     * @param _newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(
        address _newImplementation
    ) internal override onlyOwner { }

    /**
     * @notice Save funds.
     * @param _token Token address.
     * @param _amount Token amount.
     */
    function emergencySave(
        address _token,
        uint256 _amount
    ) external onlyValidAddress(_token) onlyValidAmount(_amount) onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(_amount <= balance, "2005");
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit SavedFunds(_token, _amount);
    }

    /**
     * @notice Retrieves the Manager Contract instance from the Manager Container.
     * @return IManager The Manager Contract instance.
     */
    function _getManager() internal view returns (IManager) {
        return IManager(managerContainer.manager());
    }

    /**
     * @notice Retrieves the Strategy Manager Contract instance from the Manager Contract.
     * @return IStrategyManager The Strategy Manager contract instance.
     */
    function _getStrategyManager() internal view returns (IStrategyManager) {
        return IStrategyManager(_getManager().strategyManager());
    }

    /**
     * @notice Mints an amount of receipt tokens.
     * @param _receiptToken The receipt token contract.
     * @param _recipient The recipient of the minted tokens.
     * @param _amount The amount of tokens to mint.
     * @param _tokenDecimals The decimals of the token.
     */
    function _mint(IReceiptToken _receiptToken, address _recipient, uint256 _amount, uint256 _tokenDecimals) internal {
        uint256 realAmount = _amount;
        if (_tokenDecimals > 18) {
            realAmount = _amount / (10 ** (_tokenDecimals - 18));
        } else {
            realAmount = _amount * (10 ** (18 - _tokenDecimals));
        }
        _receiptToken.mint(_recipient, realAmount);
        emit ReceiptTokensMinted(_recipient, realAmount);
    }

    /**
     * @notice Burns an amount of receipt tokens.
     * @param _receiptToken The receipt token contract.
     * @param _recipient The recipient whose tokens will be burned.
     * @param _shares The amount of shares to burn.
     * @param _totalShares The total shares in the system.
     * @param _tokenDecimals The decimals of the token.
     */
    function _burn(
        IReceiptToken _receiptToken,
        address _recipient,
        uint256 _shares,
        uint256 _totalShares,
        uint256 _tokenDecimals
    ) internal {
        uint256 burnAmount = _shares > _totalShares ? _totalShares : _shares;

        uint256 realAmount = burnAmount;
        if (_tokenDecimals > 18) {
            realAmount = burnAmount / (10 ** (_tokenDecimals - 18));
        } else {
            realAmount = burnAmount * (10 ** (18 - _tokenDecimals));
        }

        _receiptToken.burnFrom(_recipient, realAmount);
        emit ReceiptTokensBurned(_recipient, realAmount);
    }

    /**
     * @dev Renounce ownership override to avoid losing contract's ownership.
     */
    function renounceOwnership() public pure virtual override {
        revert("1000");
    }

    /**
     * @notice Ensures that the caller is the strategy manager.
     * @dev Reverts with "1000" if the caller is not the strategy manager.
     */
    modifier onlyStrategyManager() {
        require(msg.sender == address(_getStrategyManager()), "1000");
        _;
    }

    /**
     * @notice Ensures that the provided amount is valid (greater than 0).
     * @dev Reverts with "2001" if the amount is 0 or less.
     * @param _amount The amount to validate.
     */
    modifier onlyValidAmount(
        uint256 _amount
    ) {
        require(_amount > 0, "2001");
        _;
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
