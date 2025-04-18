// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IStdeUSDMin is IERC4626 {
    function cooldownShares(
        uint256 shares
    ) external returns (uint256 assets);

    function unstake(
        address receiver
    ) external;
}
