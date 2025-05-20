// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategyManager } from "@jigsaw/src/interfaces/core/IStrategyManager.sol";

import { IFeeManager } from "./extensions/interfaces/IFeeManager.sol";
import { OperationsLib } from "./libraries/OperationsLib.sol";

/**
 * @title StrategyBase v2 Contract used for common functionality through Jigsaw Strategies .
 * @author Hovooo (@hovooo)
 * @custom:oz-upgrades-from StrategyBaseUpgradeable
 */
abstract contract StrategyBaseUpgradeableV2 is Ownable2StepUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

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
     * @notice Emitted when a performance fee is taken.
     * @param token The token from which the fee is taken.
     * @param feeAddress The address that receives the fee.
     * @param amount The amount of the fee.
     */
    event FeeTaken(address indexed token, address indexed feeAddress, uint256 amount);

    /**
     * @notice Emitted when the FeeManager address is updated.
     * @param oldFeeManager The address of the old FeeManager
     * @param newFeeManager The address of the new FeeManager
     */
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);

    /**
     * @notice Contract that contains the address of the manager contract.
     */
    IManager public manager;

    /**
     * @notice Default decimals used for computations.
     */
    uint256 constant DEFAULT_DECIMALS = 18;

    /**
     * @notice Contract that contains the custom fee for the holder.
     */
    IFeeManager public feeManager;

    /**
     * @notice Storage gap to reserve storage slots in a base contract, to allow future versions of
     * StrategyBaseUpgradeableV2 to use up those slots without affecting the storage layout of child contracts.
     */
    uint256[48] __gap;

    // -- Initialization --

    /**
     * @notice Initializes the StrategyBase contract.
     * @param _initialOwner The address of the initial owner of the contract.
     */
    function __StrategyBase_init(
        address _initialOwner
    ) internal onlyInitializing {
        __Ownable_init(_initialOwner);
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    // -- Administration --

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
     * @notice Set the fee manager contract address.
     * @param _feeManager The new fee manager contract address.
     */
    function setFeeManager(
        address _feeManager
    ) external onlyOwner onlyValidAddress(_feeManager) {
        require(address(feeManager) != _feeManager, "3017");
        emit FeeManagerUpdated(address(feeManager), _feeManager);
        feeManager = IFeeManager(_feeManager);
    }

    /**
     * @dev Renounce ownership override to avoid losing contract's ownership.
     */
    function renounceOwnership() public pure virtual override {
        revert("1000");
    }

    // -- Getters --

    /**
     * @notice Retrieves the Strategy Manager Contract instance from the Manager Contract.
     * @return IStrategyManager The Strategy Manager contract instance.
     */
    function _getStrategyManager() internal view returns (IStrategyManager) {
        return IStrategyManager(manager.strategyManager());
    }

    // -- Utility functions --

    /**
     * @notice Mints an amount of receipt tokens.
     * @param _receiptToken The receipt token contract.
     * @param _recipient The recipient of the minted tokens.
     * @param _amount The amount of tokens to mint.
     * @param _tokenDecimals The decimals of the token.
     */
    function _mint(IReceiptToken _receiptToken, address _recipient, uint256 _amount, uint256 _tokenDecimals) internal {
        uint256 realAmount = _amount;
        if (_tokenDecimals > DEFAULT_DECIMALS) {
            realAmount = _amount / (10 ** (_tokenDecimals - DEFAULT_DECIMALS));
        } else {
            realAmount = _amount * (10 ** (DEFAULT_DECIMALS - _tokenDecimals));
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
        if (_tokenDecimals > DEFAULT_DECIMALS) {
            realAmount = burnAmount / (10 ** (_tokenDecimals - DEFAULT_DECIMALS));
        } else {
            realAmount = burnAmount * (10 ** (DEFAULT_DECIMALS - _tokenDecimals));
        }

        _receiptToken.burnFrom(_recipient, realAmount);
        emit ReceiptTokensBurned(_recipient, realAmount);
    }

    /**
     * @notice Takes fees from yield generated by the strategy.
     *
     * @param _token The token to take fees from.
     * @param _recipient The recipient of the fees.
     * @param _yield The yield generated by the strategy.
     *
     * @return fee The amount of fees taken.
     */
    function _takePerformanceFee(address _token, address _recipient, uint256 _yield) internal returns (uint256 fee) {
        uint256 performanceFee = feeManager.getHoldingFee({ _holding: _recipient, _strategy: address(this) });
        if (performanceFee != 0) {
            fee = OperationsLib.getFeeAbsolute(_yield, performanceFee);
            if (fee > 0) {
                address feeAddr = manager.feeAddress();
                emit FeeTaken(_token, feeAddr, fee);
                IHolding(_recipient).transfer(_token, feeAddr, fee);
            }
        }
    }

    function _genericCall(
        address _holding,
        address _contract,
        bytes memory _call
    ) internal returns (bool success, bytes memory returnData) {
        (success, returnData) = IHolding(_holding).genericCall({ _contract: _contract, _call: _call });
        if (!success) revert(OperationsLib.getRevertMsg(returnData));
    }

    // -- Modifiers --

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
