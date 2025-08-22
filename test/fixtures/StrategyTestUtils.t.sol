// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";

abstract contract StrategyTestUtils is Test {
    function _upgradeToV2() internal virtual;

    function _getStrategyStateVariables() internal view virtual returns (StrategyStateVariables memory);

    function _validateStrategyStateVariables(
        StrategyStateVariables memory a,
        StrategyStateVariables memory b
    ) internal pure {
        assertEq(a.owner, b.owner, "Owner mismatch");
        assertEq(a.manager, b.manager, "Manager mismatch");
        assertEq(a.rewardToken, b.rewardToken, "Reward token mismatch");
        assertEq(a.tokenIn, b.tokenIn, "Token in mismatch");
        assertEq(a.tokenOut, b.tokenOut, "Token out mismatch");
        assertEq(a.sharesDecimals, b.sharesDecimals, "Shares decimals mismatch");
    }

    // Test reinitialization
    function _validate_reinitialization() internal {
        StrategyStateVariables memory beforeUpgrade = _getStrategyStateVariables();

        _upgradeToV2();

        StrategyStateVariables memory afterUpgrade = _getStrategyStateVariables();

        _validateStrategyStateVariables(beforeUpgrade, afterUpgrade);
    }

    struct StrategyStateVariables {
        address owner;
        address manager;
        address rewardToken;
        address tokenIn;
        address tokenOut;
        uint256 sharesDecimals;
    }
}
