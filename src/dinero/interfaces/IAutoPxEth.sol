// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title AutoPxEth
 * @notice Autocompounding vault for (staked) pxETH, adapted from pxCVX vault system
 * @dev This contract enables autocompounding for pxETH assets and includes various fee mechanisms.
 */
interface IAutoPxEth is IERC4626 {
    /**
     * @dev Burns exactly shares from owner and sends assets of underlying tokens to receiver.
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}
