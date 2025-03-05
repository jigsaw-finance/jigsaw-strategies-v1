// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IPegStabilityModuleMin {
    function totalValue() external view returns (uint256);
    function totalRiskValue() external view returns (uint256);
    function underlyingBalance() external view returns (uint256);
}
