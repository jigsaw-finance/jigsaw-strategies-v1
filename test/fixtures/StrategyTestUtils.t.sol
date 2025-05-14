// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";

abstract contract StrategyTestUtils is Test {
    function _validateStrategyStateVariables(
        StrategyStateVariables memory a,
        StrategyStateVariables memory b
    ) internal pure {
        assertEq(a.owner, b.owner, "Owner mismatch");
        assertEq(a.manager, b.manager, "Manager mismatch");
        assertEq(a.lendingPool, b.lendingPool, "Lending pool mismatch");
        assertEq(a.rewardsController, b.rewardsController, "Rewards controller mismatch");
        assertEq(a.rewardToken, b.rewardToken, "Reward token mismatch");
        assertEq(a.tokenIn, b.tokenIn, "Token in mismatch");
        assertEq(a.tokenOut, b.tokenOut, "Token out mismatch");
        assertEq(a.sharesDecimals, b.sharesDecimals, "Shares decimals mismatch");
    }

    struct StrategyStateVariables {
        address owner;
        address manager;
        address lendingPool;
        address rewardsController;
        address rewardToken;
        address tokenIn;
        address tokenOut;
        uint256 sharesDecimals;
    }
}