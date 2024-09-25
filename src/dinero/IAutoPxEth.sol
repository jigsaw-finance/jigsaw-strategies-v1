// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

/**
 * @title AutoPxEth
 * @notice Autocompounding vault for (staked) pxETH, adapted from pxCVX vault system
 * @dev This contract enables autocompounding for pxETH assets and includes various fee mechanisms.
 */
interface IAutoPxEth is IERC4626 {
    /**
     * @notice Return the amount of assets per 1 (1e18) share
     * @return uint256 Assets
     */
    function assetsPerShare() external view returns (uint256);
}