// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface ICreditEnforcer {
    /**
     * @notice Issue the stablecoin to a recipient, check the debt cap and solvency
     * @param amount Transfer amount of the underlying
     */
    function mintStablecoin(
        uint256 amount
    ) external returns (uint256);

    /**
     * @notice Issue the stablecoin to a recipient, check the debt cap and solvency
     * @param to Receiver address
     * @param amount Transfer amount of the underlying
     */
    function mintStablecoin(address to, uint256 amount) external returns (uint256);

    /**
     * @notice Issue the savingcoin to a recipient, check the debt cap and solvency
     * @param to Receiver address
     * @param amount Underlying amount
     */
    function mintSavingcoin(address to, uint256 amount) external returns (uint256);
}
