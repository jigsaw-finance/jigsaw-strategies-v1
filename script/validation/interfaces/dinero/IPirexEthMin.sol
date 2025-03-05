// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IPirexEthMin {
    function pxEth() external view returns (address);
    function pendingDeposit() external view returns (uint256);
    function outstandingRedemptions() external view returns (uint256);
}
