// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface ICreditEnforcerMin {
    function duration() external view returns (uint256);
    function smDebtMax() external view returns (uint256);
    function psmDebtMax() external view returns (uint256);
}
