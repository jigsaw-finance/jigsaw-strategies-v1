// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";

interface IFeeManager {
    // -- Events --

    /**
     * @notice Emitted when the default fee is updated.
     *
     * @param holding The holding address the fee is updated for.
     * @param strategy The strategy address the fee is updated for.
     * @param oldFee The old fee.
     * @param newFee The new fee.
     */
    event HoldingFeeUpdated(address indexed holding, address indexed strategy, uint256 oldFee, uint256 newFee);

    // -- State variables --

    /**
     * @notice The Manager contract.
     */
    function manager() external view returns (IManager);

    // -- Administration --

    /**
     * @notice Sets performance fee for a specific `_holding` in a specific `_strategy`.
     *
     * @param _holding The address of the holding.
     * @param _strategy The address of the strategy.
     * @param _fee The performance fee to set.
     */
    function setHoldingCustomFee(address _holding, address _strategy, uint256 _fee) external;

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
    ) external;

    // -- Getters --

    /**
     * @notice Returns `_holding`'s performance fee for specified `_strategy`.
     *
     * @dev Returns default performance fee stored in StrategyManager contract, if it's set to zero.
     *
     * @param _strategy The address of the strategy.
     * @param _holding The address of the holding.
     *
     * @return `_holding`'s performance fee for `_strategy`.
     */
    function getHoldingFee(address _holding, address _strategy) external view returns (uint256);
}
