// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IPegStabilityModule {
    /**
     * @notice Redeem the underlying to the sender for stablecoin
     *
     * @param to Receiver address
     * @param amount Underlying amount
     */
    function redeem(address to, uint256 amount) external;
}
