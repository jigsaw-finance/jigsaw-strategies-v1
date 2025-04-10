// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IAutoPxEthMin {
    function totalAssets() external view returns (uint256);
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function withdrawalPenalty() external view returns (uint256);
}
