// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @notice common operations
library OperationsLib {
    uint256 internal constant FEE_FACTOR = 10_000;

    /// @notice gets the amount used as a fee
    function getFeeAbsolute(uint256 amount, uint256 fee) internal pure returns (uint256) {
        return (amount * fee) / FEE_FACTOR;
    }

    /// @notice retrieves ratio between 2 numbers
    function getRatio(uint256 numerator, uint256 denominator, uint256 precision) internal pure returns (uint256) {
        if (numerator == 0 || denominator == 0) {
            return 0;
        }
        uint256 _numerator = numerator * 10 ** (precision + 1);
        uint256 _quotient = ((_numerator / denominator) + 5) / 10;
        return (_quotient);
    }

    /// @notice approves token for spending
    function safeApprove(address token, address to, uint256 value) internal {
        (bool successEmtptyApproval,) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), to, 0));
        require(successEmtptyApproval, "OperationsLib::safeApprove: approval reset failed");

        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "OperationsLib::safeApprove: approve failed");
    }

    /// @notice gets the revert message string
    function getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "Transaction reverted silently";
        assembly {
            // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }
}
