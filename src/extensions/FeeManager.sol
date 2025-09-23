// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IStrategyManager } from "@jigsaw/src/interfaces/core/IStrategyManager.sol";

import { IFeeManager } from "./interfaces/IFeeManager.sol";

/**
 * @title FeeManager
 *
 * @notice Contract that manages custom fee configurations for Jigsaw Protocol strategies
 *
 * @dev Allows setting and retrieving custom performance fees for specific holding-strategy pairs
 * @dev Inherits from `Ownable2Step`.
 *
 * @author Hovooo (@hovooo)
 *
 * @custom:security-contact support@jigsaw.finance
 *
 */
contract FeeManager is IFeeManager, Ownable2Step {
    // -- State variables --

    /**
     * @notice The Manager contract.
     */
    IManager public override manager;

    /**
     * @notice Stores custom performance fee rates for each holding in each strategy.
     *
     * @dev Maps a holding address to a nested mapping of strategy address to fee amount.
     * @dev When a custom fee is not set (value is 0), the getHoldingFee function will return the default performance
     * fee for the strategy instead. Fee values are expressed in basis points (e.g., 1000 = 10%).
     */
    mapping(address holding => mapping(address strategy => uint256 fee)) private holdingFee;

    // -- Constructor --

    /**
     * @notice Creates a new FeeManager contract.
     * @param _initialOwner The address of the initial owner of the contract.
     * @param _manager The address of the Manager contract.
     */
    constructor(address _initialOwner, address _manager) Ownable(_initialOwner) {
        manager = IManager(_manager);
    }

    // -- Administration --

    /**
     * @notice Sets performance fee for a specific `_holding` in a specific `_strategy`.
     *
     * @param _holding The address of the holding.
     * @param _strategy The address of the strategy.
     * @param _fee The performance fee to set.
     */
    function setHoldingCustomFee(address _holding, address _strategy, uint256 _fee) external override onlyOwner {
        _setHoldingCustomFee({ _holding: _holding, _strategy: _strategy, _fee: _fee });
    }

    /**
     * @notice Sets performance fee for a list of `_holdings` in a specified `_strategies` list.
     *
     * @param _holdings The list of the holding addresses to set `_fees` for.
     * @param _strategies The list of the strategies addresses to set `_holdings`' `_fees` for.
     * @param _fees The list of performance fees to set for specified `_holdings` and `_strategies`.
     */
    function setHoldingCustomFee(
        address[] calldata _holdings,
        address[] calldata _strategies,
        uint256[] calldata _fees
    ) external override onlyOwner {
        require(_holdings.length == _strategies.length && _holdings.length == _fees.length, "3047");
        for (uint256 i = 0; i < _strategies.length; i++) {
            _setHoldingCustomFee({ _holding: _holdings[i], _strategy: _strategies[i], _fee: _fees[i] });
        }
    }

    // -- Getters --

    /**
     * @notice Returns `_holding`'s performance fee for specified `_strategy`.
     * @dev Returns default performance fee stored in StrategyManager contract, if it's set to zero.
     *
     * @param _strategy The address of the strategy.
     * @param _holding The address of the holding.
     *
     * @return `_holding`'s performance fee for `_strategy`.
     */
    function getHoldingFee(address _holding, address _strategy) external view override returns (uint256) {
        // Check if a custom fee is set for this holding-strategy pair and return if set.
        if (holdingFee[_holding][_strategy] != 0) return holdingFee[_holding][_strategy];

        // If no custom fee is set, return the default performance fee from the strategy manager
        (uint256 defaultPerformanceFee,,) = IStrategyManager(manager.strategyManager()).strategyInfo(address(_strategy));
        return defaultPerformanceFee;
    }

    // -- Utilities --

    /**
     * @notice Sets performance fee for a specific holding.
     *
     * @param _strategy The address of the strategy.
     * @param _holding The address of the holding.
     * @param _fee The custom fee to set.
     */
    function _setHoldingCustomFee(address _holding, address _strategy, uint256 _fee) private {
        require(_strategy != address(0), "3000");
        require(_holding != address(0), "3000");
        require(_fee < manager.MAX_PERFORMANCE_FEE(), "3018");
        require(holdingFee[_holding][_strategy] != _fee, "3017");

        emit HoldingFeeUpdated({
            holding: _holding,
            strategy: _strategy,
            oldFee: holdingFee[_holding][_strategy],
            newFee: _fee
        });
        holdingFee[_holding][_strategy] = _fee;
    }
}
