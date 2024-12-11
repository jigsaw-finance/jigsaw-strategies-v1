// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPirexEth {
    // Events
    /**
     * @notice Event emitted when ETH is deposited, minting pxETH, and optionally compounding into the vault.
     * @dev    Use this event to log details about the deposit, including the caller's address, the receiver's address,
     * whether compounding occurred, the deposited amount, received pxETH amount, and fee amount.
     * @param  caller          address  indexed  Address of the entity initiating the deposit.
     * @param  receiver        address  indexed  Address of the receiver of the minted pxETH or apxEth.
     * @param  shouldCompound  bool     indexed  Boolean indicating whether compounding into the vault occurred.
     * @param  deposited       uint256           Amount of ETH deposited.
     * @param  receivedAmount  uint256           Amount of pxETH minted for the receiver.
     * @param  feeAmount       uint256           Amount of pxETH distributed as fees.
     */
    event Deposit(
        address indexed caller,
        address indexed receiver,
        bool indexed shouldCompound,
        uint256 deposited,
        uint256 receivedAmount,
        uint256 feeAmount
    );

    /**
     * @notice Event emitted when a redemption is initiated by burning pxETH in return for upxETH.
     * @dev    Use this event to log details about the redemption initiation, including the redeemed asset amount,
     * post-fee amount, and the receiver's address.
     * @param  assets         uint256           Amount of pxETH burnt for the redemption.
     * @param  postFeeAmount  uint256           Amount of pxETH distributed to the receiver after deducting fees.
     * @param  receiver       address  indexed  Address of the receiver of the upxETH.
     */
    event InitiateRedemption(uint256 assets, uint256 postFeeAmount, address indexed receiver);

    /**
     * @notice Event emitted when ETH is redeemed using UpxETH.
     * @dev    Use this event to log details about the redemption, including the tokenId, redeemed asset amount, and the
     * receiver's address.
     * @param  tokenId   uint256           Identifier for the redemption batch.
     * @param  assets    uint256           Amount of ETH redeemed.
     * @param  receiver  address  indexed  Address of the receiver of the redeemed ETH.
     */
    event RedeemWithUpxEth(uint256 tokenId, uint256 assets, address indexed receiver);

    /**
     * @notice Event emitted when pxETH is redeemed for ETH with fees.
     * @dev    Use this event to log details about pxETH redemption, including the redeemed asset amount, post-fee
     * amount, and the receiver's address.
     * @param  assets         uint256           Amount of pxETH redeemed.
     * @param  postFeeAmount  uint256           Amount of ETH received by the receiver after deducting fees.
     * @param  _receiver      address  indexed  Address of the receiver of the redeemed ETH.
     */
    event RedeemWithPxEth(uint256 assets, uint256 postFeeAmount, address indexed _receiver);
    /**
     * @notice Handle pxETH minting in return for ETH deposits
     * @dev    This function handles the minting of pxETH in return for ETH deposits.
     * @param  receiver        address  Receiver of the minted pxETH or apxEth
     * @param  shouldCompound  bool     Whether to also compound into the vault
     * @return postFeeAmount   uint256  pxETH minted for the receiver
     * @return feeAmount       uint256  pxETH distributed as fees
     */

    function deposit(
        address receiver,
        bool shouldCompound
    ) external payable returns (uint256 postFeeAmount, uint256 feeAmount);

    /**
     * @notice Instant redeem back ETH using pxETH
     * @dev    This function burns pxETH, calculates fees, and transfers ETH to the receiver.
     * @param  assets        uint256   Amount of pxETH to redeem.
     * @param  receiver      address   Address of the ETH receiver.
     * @return postFeeAmount  uint256   Post-fee amount for the receiver.
     * @return feeAmount      uint256  Fee amount sent to the PirexFees.
     */
    function instantRedeemWithPxEth(
        uint256 assets,
        address receiver
    ) external returns (uint256 postFeeAmount, uint256 feeAmount);
}
