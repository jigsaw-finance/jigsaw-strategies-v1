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

import { StrategyBaseUpgradeable } from "../../src/StrategyBaseUpgradeable.sol";
import { OperationsLib } from "../../src/libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../../src/libraries/StrategyConfigLib.sol";

contract StrategyMockImpl is IStrategy, StrategyBaseUpgradeable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    error OperationNotSupported();

    struct InitializerParams {
        address owner;
        address manager;
        address jigsawRewardToken;
        uint256 jigsawRewardDuration;
        address tokenIn;
        address tokenOut;
    }

    address public override tokenIn;

    address public override tokenOut;

    address public override rewardToken;

    IReceiptToken public override receiptToken;

    uint256 public override sharesDecimals;

    uint256 public constant DECIMAL_DIFF = 1e12;

    mapping(address recipient => IStrategy.RecipientInfo info) public override recipients;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        InitializerParams memory _params
    ) public initializer {
        require(_params.manager != address(0), "3065");
        require(_params.jigsawRewardToken != address(0), "3000");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        manager = IManager(_params.manager);
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: manager.receiptTokenFactory(),
                _receiptTokenName: "Mock Receipt Token",
                _receiptTokenSymbol: "MRT"
            })
        );
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
