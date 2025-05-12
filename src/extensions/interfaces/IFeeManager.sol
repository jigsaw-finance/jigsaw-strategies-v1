// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IFeeManager {
    /**
     * @notice Emitted when the default fee is updated.
     * @param strategy The strategy address.
     * @param holding The holding address.
     * @param oldFee The previous fee.
     * @param newFee The new fee.
     */
    event HoldingCustomFeeUpdated(address strategy, address holding, uint256 indexed oldFee, uint256 indexed newFee);

    /**
     * @notice Sets a custom fee for a list of holdings.
     * @param _strategies The address list of the strategies.
     * @param _holdings The address list of the holdings.
     * @param _vals The custom fee list to set.
     */
    function setHoldingCustomFees(address[] calldata _strategies, address[] calldata _holdings, uint256[] calldata _vals) external;

    /**
     * @notice Sets a custom fee for a specific holding.
     * @param _strategy The address of the strategy.
     * @param _holding The address of the holding.
     * @param _val The custom fee to set.
     */
    function setHoldingCustomFee(address _strategy, address _holding, uint256 _val) external;

    /**
     * @notice Retrieves the custom holding fee.
     * @param _strategy The address of the strategy.
     * @param _holding The address of the holding.
     * @return The holding's custom fee or default.
     */
    function getHoldingFee(address _strategy, address _holding) external view returns (uint256);
}