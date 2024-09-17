// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { HoldingManager } from "@jigsaw/src/HoldingManager.sol";
import { JigsawUSD } from "@jigsaw/src/JigsawUSD.sol";
import { LiquidationManager } from "@jigsaw/src/LiquidationManager.sol";
import { Manager } from "@jigsaw/src/Manager.sol";
import { ManagerContainer } from "@jigsaw/src/ManagerContainer.sol";
import { ReceiptToken } from "@jigsaw/src/ReceiptToken.sol";
import { ReceiptTokenFactory } from "@jigsaw/src/ReceiptTokenFactory.sol";
import { SharesRegistry } from "@jigsaw/src/SharesRegistry.sol";
import { StablesManager } from "@jigsaw/src/StablesManager.sol";
import { StrategyManager } from "@jigsaw/src/StrategyManager.sol";

import { ILiquidationManager } from "@jigsaw/src/interfaces/core/ILiquidationManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";
import { IStrategyManager } from "@jigsaw/src/interfaces/core/IStrategyManager.sol";

import { SampleOracle } from "@jigsaw/test/utils/mocks/SampleOracle.sol";
import { SampleTokenERC20 } from "@jigsaw/test/utils/mocks/SampleTokenERC20.sol";
import { StrategyWithoutRewardsMock } from "@jigsaw/test/utils/mocks/StrategyWithoutRewardsMock.sol";
import { wETHMock } from "@jigsaw/test/utils/mocks/wETHMock.sol";

abstract contract BasicContractsFixture is Test {
    address internal constant OWNER = address(uint160(uint256(keccak256("owner"))));

    using Math for uint256;

    IReceiptToken public receiptTokenReference;
    HoldingManager internal holdingManager;
    LiquidationManager internal liquidationManager;
    Manager internal manager;
    ManagerContainer internal managerContainer;
    JigsawUSD internal jUsd;
    ReceiptTokenFactory internal receiptTokenFactory;
    SampleOracle internal usdcOracle;
    SampleOracle internal jUsdOracle;
    SampleTokenERC20 internal usdc;
    wETHMock internal weth;
    SharesRegistry internal sharesRegistry;
    SharesRegistry internal wethSharesRegistry;
    StablesManager internal stablesManager;
    StrategyManager internal strategyManager;
    StrategyWithoutRewardsMock internal strategyWithoutRewardsMock;

    // collateral to registry mapping
    mapping(address => address) internal registries;

    function init() public {
        vm.startPrank(OWNER);
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        usdc = new SampleTokenERC20("USDC", "USDC", 0);
        usdcOracle = new SampleOracle();

        weth = new wETHMock();
        SampleOracle wethOracle = new SampleOracle();

        jUsdOracle = new SampleOracle();

        manager = new Manager(OWNER, address(usdc), address(weth), address(jUsdOracle), bytes(""));
        managerContainer = new ManagerContainer(OWNER, address(manager));

        jUsd = new JigsawUSD(OWNER, address(managerContainer));
        jUsd.updateMintLimit(type(uint256).max);

        holdingManager = new HoldingManager(OWNER, address(managerContainer));
        liquidationManager = new LiquidationManager(OWNER, address(managerContainer));
        stablesManager = new StablesManager(OWNER, address(managerContainer), address(jUsd));
        strategyManager = new StrategyManager(OWNER, address(managerContainer));

        sharesRegistry =
            new SharesRegistry(OWNER, address(managerContainer), address(usdc), address(usdcOracle), bytes(""), 50_000);
        stablesManager.registerOrUpdateShareRegistry(address(sharesRegistry), address(usdc), true);
        registries[address(usdc)] = address(sharesRegistry);

        wethSharesRegistry =
            new SharesRegistry(OWNER, address(managerContainer), address(weth), address(wethOracle), bytes(""), 50_000);
        stablesManager.registerOrUpdateShareRegistry(address(wethSharesRegistry), address(weth), true);
        registries[address(weth)] = address(wethSharesRegistry);

        receiptTokenFactory = new ReceiptTokenFactory(OWNER);
        receiptTokenReference = IReceiptToken(new ReceiptToken());
        receiptTokenFactory.setReceiptTokenReferenceImplementation(address(receiptTokenReference));

        manager.setReceiptTokenFactory(address(receiptTokenFactory));

        manager.setFeeAddress(address(uint160(uint256(keccak256(bytes("Fee address"))))));

        manager.whitelistToken(address(usdc));
        manager.whitelistToken(address(weth));

        manager.setStablecoinManager(address(stablesManager));
        manager.setHoldingManager(address(holdingManager));
        manager.setLiquidationManager(address(liquidationManager));
        manager.setStrategyManager(address(strategyManager));

        strategyWithoutRewardsMock = new StrategyWithoutRewardsMock({
            _managerContainer: address(managerContainer),
            _tokenIn: address(usdc),
            _tokenOut: address(usdc),
            _rewardToken: address(0),
            _receiptTokenName: "RUsdc-Mock",
            _receiptTokenSymbol: "RUSDCM"
        });
        strategyManager.addStrategy(address(strategyWithoutRewardsMock));
        vm.stopPrank();
    }

    // Utility functions

    function initiateUser(address _user, address _token, uint256 _tokenAmount) public returns (address userHolding) {
        return initiateUser(_user, _token, _tokenAmount, true);
    }

    function initiateUser(address _user, address _token, uint256 _tokenAmount, bool _adjust) public returns (address userHolding) {
        IERC20Metadata collateralContract = IERC20Metadata(_token);
        vm.startPrank(_user, _user);

        deal(_token, _user, _tokenAmount, _adjust);

        // Create holding for user
        userHolding = holdingManager.createHolding();

        // Deposit to the holding
        collateralContract.approve(address(holdingManager), _tokenAmount);
        holdingManager.deposit(_token, _tokenAmount);

        vm.stopPrank();
    }

    function _getCollateralAmountForUSDValue(
        address _collateral,
        uint256 _jUSDAmount,
        uint256 _exchangeRate
    ) private view returns (uint256 totalCollateral) {
        // calculate based on the USD value
        totalCollateral = (1e18 * _jUSDAmount * manager.EXCHANGE_RATE_PRECISION()) / (_exchangeRate * 1e18);

        // transform from 18 decimals to collateral's decimals
        uint256 collateralDecimals = IERC20Metadata(_collateral).decimals();

        if (collateralDecimals > 18) {
            totalCollateral = totalCollateral * (10 ** (collateralDecimals - 18));
        } else if (collateralDecimals < 18) {
            totalCollateral = totalCollateral / (10 ** (18 - collateralDecimals));
        }
    }

    // Modifiers

    modifier notOwnerNotZero(address _user) {
        vm.assume(_user != OWNER);
        vm.assume(_user != address(0));
        _;
    }
}
