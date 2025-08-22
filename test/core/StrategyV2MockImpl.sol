// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { StrategyBaseUpgradeableV2 } from "../../src/StrategyBaseUpgradeableV2.sol";
import { IFeeManager } from "../../src/extensions/interfaces/IFeeManager.sol";
import { OperationsLib } from "../../src/libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../../src/libraries/StrategyConfigLib.sol";

contract StrategyV2MockImpl is IStrategy, StrategyBaseUpgradeableV2 {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    error OperationNotSupported();

    address public override tokenIn;

    address public override tokenOut;

    address public override rewardToken;

    IReceiptToken public override receiptToken;

    uint256 public override sharesDecimals;

    uint256 public constant DECIMAL_DIFF = 1e12;

    mapping(address recipient => IStrategy.RecipientInfo info) public override recipients;

    struct InitializerParams {
        address feeManager;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        InitializerParams memory _params
    ) public reinitializer(2) {
        require(_params.feeManager != address(0), "3000");
        feeManager = IFeeManager(_params.feeManager);
    }

    function deposit(
        address,
        uint256 _amount,
        address,
        bytes calldata
    ) external override nonReentrant onlyValidAmount(_amount) onlyStrategyManager returns (uint256, uint256) {
        revert OperationNotSupported();
    }

    function withdraw(
        uint256,
        address,
        address,
        bytes calldata
    ) external override nonReentrant onlyStrategyManager returns (uint256, uint256, int256, uint256) {
        revert OperationNotSupported();
    }

    function claimRewards(
        address,
        bytes calldata
    ) external pure override returns (uint256[] memory, address[] memory) {
        revert OperationNotSupported();
    }

    function getReceiptTokenAddress() external view override returns (address) {
        return address(receiptToken);
    }
}
