// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "../fixtures/BasicContractsFixture.t.sol";
import "forge-std/Test.sol";

import { FeeManager } from "../../src/extensions/FeeManager.sol";

contract FeeManagerTest is BasicContractsFixture {
    address private holding = address(0x2);
    address private strategy = address(0x3);
    uint256 private customFee = 500; // 5%

    function setUp() public {
        init();
    }

    function test_setsCustomFeeForHoldingAndStrategy() public {
        vm.prank(OWNER);
        feeManager.setHoldingCustomFee(holding, strategy, customFee);

        uint256 fee = feeManager.getHoldingFee(holding, strategy);
        assertEq(fee, customFee, "Custom fee should be set correctly");
    }

    function test_revertsOnSettingFeeAboveMax() public {
        uint256 invalidFee = manager.MAX_PERFORMANCE_FEE() + 1;

        vm.prank(OWNER);
        vm.expectRevert(bytes("3018"));
        feeManager.setHoldingCustomFee(holding, strategy, invalidFee);
    }

    function test_revertsOnSettingFeeForZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(bytes("3000"));
        feeManager.setHoldingCustomFee(address(0), strategy, customFee);

        vm.prank(OWNER);
        vm.expectRevert(bytes("3000"));
        feeManager.setHoldingCustomFee(holding, address(0), customFee);
    }

    function test_returnsDefaultFeeWhenCustomFeeNotSet() public {
        (uint256 defaultPerformanceFee,,) = IStrategyManager(manager.strategyManager()).strategyInfo(address(strategy));
        uint256 fee = feeManager.getHoldingFee(holding, strategy);
        assertEq(fee, defaultPerformanceFee, "Should return default fee when custom fee is not set");
    }

    function test_revertsOnSettingSameFee() public {
        vm.prank(OWNER);
        feeManager.setHoldingCustomFee(holding, strategy, customFee);

        vm.prank(OWNER);
        vm.expectRevert(bytes("3017"));
        feeManager.setHoldingCustomFee(holding, strategy, customFee);
    }

    function test_revertsOnInvalidNumberOfParametersPassed() public {
        address[] memory holdings = new address[](2);
        address[] memory strategies = new address[](2);
        uint256[] memory fees = new uint256[](3);

        holdings[0] = address(0x3);
        holdings[1] = address(0x4);
        strategies[0] = address(0x5);
        strategies[1] = address(0x6);
        fees[0] = customFee;
        fees[1] = customFee + 100;
        fees[2] = customFee + 200;

        vm.prank(OWNER);
        vm.expectRevert(bytes("3047"));
        feeManager.setHoldingCustomFee(holdings, strategies, fees);
    }

    function test_updatesFeeForMultipleHoldingsAndStrategies() public {
        address[] memory holdings = new address[](2);
        address[] memory strategies = new address[](2);
        uint256[] memory fees = new uint256[](2);

        holdings[0] = holding;
        holdings[1] = address(0x4);
        strategies[0] = strategy;
        strategies[1] = address(0x5);
        fees[0] = customFee;
        fees[1] = customFee + 100;

        vm.prank(OWNER);
        feeManager.setHoldingCustomFee(holdings, strategies, fees);

        assertEq(feeManager.getHoldingFee(holdings[0], strategies[0]), customFee, "First fee should be set correctly");
        assertEq(
            feeManager.getHoldingFee(holdings[1], strategies[1]), customFee + 100, "Second fee should be set correctly"
        );
    }
}
