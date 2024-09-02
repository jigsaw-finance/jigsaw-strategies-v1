// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IManagerContainer } from "@jigsaw/src/interfaces/core/IManagerContainer.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";
import { IStrategyManager } from "@jigsaw/src/interfaces/core/IStrategyManager.sol";

/// @title StrategyBase contract used for any Aave strategy
/// @author Cosmin Grigore (@gcosmintech)
abstract contract StrategyBase is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice emitted when a new underlying is added to the whitelist
    event UnderlyingAdded(address indexed newAddress);
    /// @notice emitted when a new underlying is removed from the whitelist
    event UnderlyingRemoved(address indexed old);
    /// @notice emitted when the address is updated
    event StrategyManagerUpdated(address indexed old, address indexed newAddress);
    /// @notice emitted when funds are saved in case of an emergency
    event SavedFunds(address indexed token, uint256 amount);
    /// @notice emitted when receipt tokens are minted
    event ReceiptTokensMinted(address indexed receipt, uint256 amount);
    /// @notice emitted when receipt tokens are burned
    event ReceiptTokensBurned(address indexed receipt, uint256 amount);

    /// @notice contract that contains the address of the manager contract
    IManagerContainer public managerContainer;

    constructor(address _owner) Ownable(_owner) { }

    /// @notice save funds
    /// @param _token token address
    /// @param _amount token amount
    function emergencySave(
        address _token,
        uint256 _amount
    ) external onlyValidAddress(_token) onlyValidAmount(_amount) onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(_amount <= balance, "2005");
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit SavedFunds(_token, _amount);
    }

    function _getManager() internal view returns (IManager) {
        return IManager(managerContainer.manager());
    }

    function _getStrategyManager() internal view returns (IStrategyManager) {
        return IStrategyManager(_getManager().strategyManager());
    }

    /// @notice mints an amount of receipt tokens
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

    /// @notice burns an amount of receipt tokens
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

    // @dev renounce ownership override to avoid losing contract's ownership
    function renounceOwnership() public pure virtual override {
        revert("1000");
    }

    modifier onlyStrategyManager() {
        require(msg.sender == address(_getStrategyManager()), "1000");
        _;
    }

    modifier onlyValidAmount(uint256 _amount) {
        require(_amount > 0, "2001");
        _;
    }

    modifier onlyValidAddress(address _addr) {
        require(_addr != address(0), "3000");
        _;
    }
}
