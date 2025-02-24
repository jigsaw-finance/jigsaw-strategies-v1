// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface ISavingModule {
    /**
     * @notice Burn srUSD from the sender address and mint rUSD to the other
     *  @param to Receiver address
     *  @param amount Minted rUSD
     */
    function redeem(address to, uint256 amount) external;

    /**
     * @notice Current price of srUSD in rUSD (always >= 1e8)
     * @return uint256 Price
     */
    function currentPrice() external view returns (uint256);

    /**
     * @notice Current redeem fee
     * @return uint256 fee
     */
    function redeemFee() external view returns (uint256);
}
