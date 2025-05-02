// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ISdeUsdMin is IERC4626 {
    function cooldownShares(
        uint256 shares
    ) external returns (uint256 assets);

    function unstake(
        address receiver
    ) external;
}
