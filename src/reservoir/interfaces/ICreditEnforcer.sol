// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface ICreditEnforcer {
    /**
     * @notice Issue the stablecoin to a recipient, check the debt cap and solvency
     * @param amount Transfer amount of the underlying
     */
    function mintStablecoin(address to, uint256 amount) external returns (uint256);
}
