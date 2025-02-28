// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@pendle/interfaces/IPLimitRouter.sol";

interface IPendleMarketMin {
    function redeemRewards(
        address user
    ) external returns (uint256[] memory);
    function getRewardTokens() external view returns (address[] memory);
}
