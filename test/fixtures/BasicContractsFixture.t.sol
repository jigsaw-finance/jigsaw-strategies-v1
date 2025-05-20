// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { stdJson as StdJson } from "forge-std/StdJson.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { HoldingManager } from "@jigsaw/src/HoldingManager.sol";
import { JigsawUSD } from "@jigsaw/src/JigsawUSD.sol";
import { LiquidationManager } from "@jigsaw/src/LiquidationManager.sol";
import { Manager } from "@jigsaw/src/Manager.sol";
import { ReceiptToken } from "@jigsaw/src/ReceiptToken.sol";
import { ReceiptTokenFactory } from "@jigsaw/src/ReceiptTokenFactory.sol";
import { SharesRegistry } from "@jigsaw/src/SharesRegistry.sol";
import { StablesManager } from "@jigsaw/src/StablesManager.sol";
import { StrategyManager } from "@jigsaw/src/StrategyManager.sol";

import { ILiquidationManager } from "@jigsaw/src/interfaces/core/ILiquidationManager.sol";
import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { ISharesRegistry } from "@jigsaw/src/interfaces/core/ISharesRegistry.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";
import { IStrategyManager } from "@jigsaw/src/interfaces/core/IStrategyManager.sol";

import { SampleOracle } from "@jigsaw/test/utils/mocks/SampleOracle.sol";
import { SampleTokenERC20 } from "@jigsaw/test/utils/mocks/SampleTokenERC20.sol";
import { StrategyWithoutRewardsMock } from "@jigsaw/test/utils/mocks/StrategyWithoutRewardsMock.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";
import { FeeManager } from "../../src/extensions/FeeManager.sol";

import { IWETH9 as IWETH } from "../../src/dinero/interfaces/IWETH9.sol";

abstract contract BasicContractsFixture is Test {
    using StdJson for string;
    using Math for uint256;
    using SafeERC20 for IERC20Metadata;

    address internal constant OWNER = 0xf5a1Dc8f36ce7cf89a82BBd817F74EC56e7fDCd8;

    IReceiptToken public receiptTokenReference;
    HoldingManager internal holdingManager;
    LiquidationManager internal liquidationManager;
    Manager internal manager;
    JigsawUSD internal jUsd;
    ReceiptTokenFactory internal receiptTokenFactory;
    SampleOracle internal usdcOracle;
    SampleOracle internal jUsdOracle;
    SampleTokenERC20 internal usdc;
    IWETH internal weth;
    SharesRegistry internal sharesRegistry;
    SharesRegistry internal wethSharesRegistry;
    StablesManager internal stablesManager;
    StrategyManager internal strategyManager;
    StrategyWithoutRewardsMock internal strategyWithoutRewardsMock;
    StakerLightFactory internal stakerFactory;
    FeeManager internal feeManager;

    address internal jRewards;

    // collateral to registry mapping
    mapping(address => address) internal registries;

    function init() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.startPrank(OWNER);
        deal(OWNER, 100_000e18);

        usdc = new SampleTokenERC20("USDC", "USDC", 0);
        usdcOracle = new SampleOracle();

        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        SampleOracle wethOracle = new SampleOracle();

        jUsdOracle = new SampleOracle();

        manager = new Manager(OWNER, address(weth), address(jUsdOracle), bytes(""));

        jUsd = new JigsawUSD(OWNER, address(manager));
        jUsd.updateMintLimit(type(uint256).max);

        holdingManager = new HoldingManager(OWNER, address(manager));
        liquidationManager = new LiquidationManager(OWNER, address(manager));
        stablesManager = new StablesManager(OWNER, address(manager), address(jUsd));
        strategyManager = new StrategyManager(OWNER, address(manager));
        feeManager = new FeeManager(OWNER, address(manager));

        sharesRegistry = new SharesRegistry(
            OWNER,
            address(manager),
            address(usdc),
            address(usdcOracle),
            bytes(""),
            ISharesRegistry.RegistryConfig({
                collateralizationRate: 50_000,
                liquidationBuffer: 5e3,
                liquidatorBonus: 8e3
            })
        );

        wethSharesRegistry = new SharesRegistry(
            OWNER,
            address(manager),
            address(weth),
            address(wethOracle),
            bytes(""),
            ISharesRegistry.RegistryConfig({
                collateralizationRate: 50_000,
                liquidationBuffer: 5e3,
                liquidatorBonus: 8e3
            })
        );

        receiptTokenReference = IReceiptToken(new ReceiptToken());
        receiptTokenFactory = new ReceiptTokenFactory(OWNER, address(receiptTokenReference));

        manager.setReceiptTokenFactory(address(receiptTokenFactory));

        manager.setFeeAddress(address(uint160(uint256(keccak256(bytes("Fee address"))))));

        manager.whitelistToken(address(usdc));
        manager.whitelistToken(address(weth));

        manager.setStablecoinManager(address(stablesManager));
        manager.setHoldingManager(address(holdingManager));
        manager.setLiquidationManager(address(liquidationManager));
        manager.setStrategyManager(address(strategyManager));

        strategyWithoutRewardsMock = new StrategyWithoutRewardsMock({
            _manager: address(manager),
            _tokenIn: address(usdc),
            _tokenOut: address(usdc),
            _rewardToken: address(0),
            _receiptTokenName: "RUsdc-Mock",
            _receiptTokenSymbol: "RUSDCM"
        });
        strategyManager.addStrategy(address(strategyWithoutRewardsMock));

        stablesManager.registerOrUpdateShareRegistry(address(sharesRegistry), address(usdc), true);
        registries[address(usdc)] = address(sharesRegistry);

        stablesManager.registerOrUpdateShareRegistry(address(wethSharesRegistry), address(weth), true);
        registries[address(weth)] = address(wethSharesRegistry);

        jRewards = address(new ERC20Mock());
        stakerFactory =
            new StakerLightFactory({ _initialOwner: OWNER, _referenceImplementation: address(new StakerLight()) });

        // save deployed addresses to configs
        Strings.toHexString(uint160(OWNER), 20).write("./deployment-config/00_CommonConfig.json", ".INITIAL_OWNER");
        Strings.toHexString(uint160(address(manager)), 20).write("./deployment-config/00_CommonConfig.json", ".MANAGER");
        Strings.toHexString(uint160(jRewards), 20).write("./deployment-config/00_CommonConfig.json", ".JIGSAW_REWARDS");
        Strings.toHexString(uint160(address(strategyManager)), 20).write(
            "./deployment-config/00_CommonConfig.json", ".STRATEGY_MANAGER"
        );
        Strings.toHexString(uint160(address(stakerFactory)), 20).write("./deployments.json", ".STAKER_FACTORY");

        vm.stopPrank();
    }

    // Utility functions

    function initiateUser(address _user, address _token, uint256 _tokenAmount) public returns (address userHolding) {
        return initiateUser(_user, _token, _tokenAmount, true);
    }

    function initiateUser(
        address _user,
        address _token,
        uint256 _tokenAmount,
        bool _adjust
    ) public returns (address userHolding) {
        IERC20Metadata collateralContract = IERC20Metadata(_token);
        vm.startPrank(_user, _user);

        deal(_token, _user, _tokenAmount, _adjust);

        // Create holding for user
        userHolding = holdingManager.createHolding();

        // Deposit to the holding
        // TODO (Tigran Arakelyan): Use safeIncreaseAllowance instead of approve
        // https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#SafeERC20-safeApprove-contract-IERC20-address-uint256-
        // Meant to be used with tokens that require the approval to be set to zero before setting it to a non-zero value, such as USDT.
        // collateralContract.approve(address(holdingManager), _tokenAmount);
        collateralContract.safeIncreaseAllowance(address(holdingManager), _tokenAmount);

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

    function _getFeeAbsolute(uint256 amount, uint256 fee) internal pure returns (uint256) {
        return (amount * fee) / 10_000 + (amount * fee % 10_000 == 0 ? 0 : 1);
    }

    // Modifiers

    modifier notOwnerNotZero(
        address _user
    ) {
        vm.assume(_user != OWNER);
        vm.assume(_user != address(0));
        _;
    }
}
