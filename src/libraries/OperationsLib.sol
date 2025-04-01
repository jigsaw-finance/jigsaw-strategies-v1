// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/**
 * @title OperationsLib
 * @notice Provides utility functions for common operations, such as fee calculations, ratios, approvals, and revert
 * message handling.
 */
library OperationsLib {
    uint256 internal constant FEE_FACTOR = 10_000;

    enum Rounding {
        Floor, // Toward negative infinity
        Ceil // Toward positive infinity

    }

    /**
     * @notice Calculate the absolute fee from the given amount and fee percentage.
     * @dev Rounds the fee amount up to avoid any precision loss vulnerabilities.
     * @param amount The original amount to apply the fee on.
     * @param fee The fee percentage to be applied.
     * @return The calculated fee value.
     */
    function getFeeAbsolute(uint256 amount, uint256 fee) internal pure returns (uint256) {
        return (amount * fee) / FEE_FACTOR + (amount * fee % FEE_FACTOR == 0 ? 0 : 1);
    }

    /**
     * @notice Get the ratio of two numbers with a specified precision and rounding option.
     *
     * @param numerator The numerator in the ratio calculation.
     * @param denominator The denominator in the ratio calculation.
     * @param precision The number of decimals to include in the result.
     * @param rounding The rounding direction (Ceil or Floor).
     *
     * @return The calculated ratio.
     */
    function getRatio(
        uint256 numerator,
        uint256 denominator,
        uint256 precision,
        Rounding rounding
    ) internal pure returns (uint256) {
        if (numerator == 0 || denominator == 0) {
            return 0;
        }

        uint256 _numerator = numerator * 10 ** precision;
        uint256 _quotient = _numerator / denominator;

        // Round up if necessary
        if (rounding == Rounding.Ceil && _numerator % denominator > 0) {
            _quotient += 1;
        }

        return (_quotient);
    }

    /**
     * @notice Decode and return the revert message from a failed transaction.
     * @param _returnData The return data of a failed external call.
     * @return The decoded revert message string.
     */
    function getRevertMsg(
        bytes memory _returnData
    ) internal pure returns (string memory) {
        // If the return data length is less than 68, then the transaction failed without a specific revert message
        if (_returnData.length < 68) return "Transaction reverted silently";
        assembly {
            // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // Return the revert string message
    }
}
