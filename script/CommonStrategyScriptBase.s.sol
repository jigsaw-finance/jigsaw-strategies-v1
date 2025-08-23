// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Script, stdJson as StdJson } from "forge-std/Script.sol";

import { AaveV3Strategy } from "../src/aave/AaveV3Strategy.sol";
import { DineroStrategy } from "../src/dinero/DineroStrategy.sol";

import { ElixirStrategy } from "../src/elixir/ElixirStrategy.sol";
import { PendleStrategy } from "../src/pendle/PendleStrategy.sol";
import { ReservoirSavingStrategy } from "../src/reservoir/ReservoirSavingStrategy.sol";

import { AaveV3StrategyV2 } from "../src/aave/AaveV3StrategyV2.sol";
import { DineroStrategyV2 } from "../src/dinero/DineroStrategyV2.sol";
import { PendleStrategyV2 } from "../src/pendle/PendleStrategyV2.sol";
import { ReservoirSavingStrategyV2 } from "../src/reservoir/ReservoirSavingStrategyV2.sol";

import { ValidateInterface } from "./validation/ValidateInterface.s.sol";

contract CommonStrategyScriptBase is Script, ValidateInterface {
    using StdJson for string;

    struct AaveStrategyParams {
        address rewardToken; // Aave reward token used in the integrated pool;
        uint256 jigsawRewardDuration; // the duration of the jigsaw rewards (jPoints) distribution;
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of the Aave receipt token (aToken)
    }

    struct PendleStrategyParams {
        address pendleMarket; // The address of the Pendle's Market contract.
        uint256 jigsawRewardDuration; // the duration of the jigsaw rewards (jPoints) distribution;
        address tokenIn; // The address of the LP token
        address rewardToken; // The address of the Pendle primary reward token
    }

    struct ReservoirSavingStrategyParams {
        address creditEnforcer; // The address of the Reservoir's CreditEnforcer contract
        address pegStabilityModule; // The Reservoir's PegStabilityModule contract.
        address savingModule; // The Reservoir's SavingModule contract.
        address rUSD; // The Reservoir's rUSD stablecoin.
        uint256 jigsawRewardDuration; // the duration of the jigsaw rewards (jPoints) distribution;
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of the Pendle receipt token
    }

    struct DineroStrategyParams {
        address pirexEth; // The address of the PirexEth
        address autoPirexEth; // The address of the AutoPirexEth
        uint256 jigsawRewardDuration; // The address of the initial Jigsaw reward distribution duration for the strategy
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of the PirexEth receipt token (pxEth)
    }

    struct ElixirStrategyParams {
        uint256 jigsawRewardDuration; // The address of the initial Jigsaw reward distribution duration for the strategy
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of Elixir's receipt token
        address deUSD; // The Elixir's deUSD stablecoin.
        address[] initialPools; // The address array of the UniswapV3 pools
        ElixirStrategy.SwapDirection[] swapDirections;
        bytes[] swapPaths;
    }

    uint256 constant DEFAULT_REWARDS_DURATION = 194 days;

    bytes32 constant ELIXIR_STRATEGY = keccak256("ElixirStrategy");
    bytes32 constant AAVE_STRATEGY_V2 = keccak256("AaveV3StrategyV2");
    bytes32 constant PENDLE_STRATEGY_V2 = keccak256("PendleStrategyV2");
    bytes32 constant RESERVOIR_STRATEGY_V2 = keccak256("ReservoirSavingStrategyV2");
    bytes32 constant DINERO_STRATEGY_V2 = keccak256("DineroStrategyV2");

    ////////////////
    // DEPRECATED //
    ////////////////
    bytes32 constant AAVE_STRATEGY = keccak256("AaveV3Strategy");
    bytes32 constant PENDLE_STRATEGY = keccak256("PendleStrategy");
    bytes32 constant RESERVOIR_STRATEGY = keccak256("ReservoirSavingStrategy");
    bytes32 constant DINERO_STRATEGY = keccak256("DineroStrategy");

    AaveStrategyParams[] internal aaveStrategyParams;
    PendleStrategyParams[] internal pendleStrategyParams;
    ReservoirSavingStrategyParams[] internal reservoirSavingStrategyParams;
    DineroStrategyParams[] internal dineroStrategyParams;
    ElixirStrategyParams[] internal elixirStrategyParams;

    modifier broadcast() {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        _;
        vm.stopBroadcast();
    }

    modifier broadcastFrom(
        uint256 _pk
    ) {
        vm.startBroadcast(_pk);
        _;
        vm.stopBroadcast();
    }

    function _buildProxyData(
        string calldata _strategy
    ) internal returns (bytes[] memory data) {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");
        string memory deployments = vm.readFile("./deployments.json");

        address owner = commonConfig.readAddress(".INITIAL_OWNER");
        address manager = commonConfig.readAddress(".MANAGER");
        address jigsawRewardToken = commonConfig.readAddress(".JIGSAW_REWARDS");
        address stakerFactory = deployments.readAddress(".STAKER_FACTORY");
        address feeManager = commonConfig.readAddress(".FEE_MANAGER");

        _validateManager(manager);
        _validateErc20(jigsawRewardToken);
        _validateStakerFactory(stakerFactory);

        if (keccak256(bytes(_strategy)) == AAVE_STRATEGY) {
            string memory aaveConfig = vm.readFile("./deployment-config/01_AaveV3StrategyConfig.json");
            address aaveLendingPool = aaveConfig.readAddress(".LENDING_POOL");
            address aaveRewardsController = aaveConfig.readAddress(".REWARDS_CONTROLLER");

            _validateAaveLendingPool(aaveLendingPool);
            _validateAaveRewardsController(aaveRewardsController);

            _populateAaveArray();

            data = new bytes[](aaveStrategyParams.length);

            for (uint256 i = 0; i < aaveStrategyParams.length; i++) {
                _validateErc20(aaveStrategyParams[i].tokenIn);
                _validateAaveToken(aaveStrategyParams[i].tokenOut);

                data[i] = abi.encodeCall(
                    AaveV3Strategy.initialize,
                    AaveV3Strategy.InitializerParams({
                        owner: owner,
                        manager: manager,
                        stakerFactory: stakerFactory,
                        lendingPool: aaveLendingPool,
                        rewardsController: aaveRewardsController,
                        jigsawRewardToken: jigsawRewardToken,
                        rewardToken: aaveStrategyParams[i].rewardToken,
                        jigsawRewardDuration: aaveStrategyParams[i].jigsawRewardDuration,
                        tokenIn: aaveStrategyParams[i].tokenIn,
                        tokenOut: aaveStrategyParams[i].tokenOut
                    })
                );
            }

            return data;
        }

        if (keccak256(bytes(_strategy)) == AAVE_STRATEGY_V2) {
            string memory aaveConfig = vm.readFile("./deployment-config/01_AaveV3StrategyConfig.json");
            address aaveLendingPool = aaveConfig.readAddress(".LENDING_POOL");
            address aaveRewardsController = aaveConfig.readAddress(".REWARDS_CONTROLLER");

            _validateAaveLendingPool(aaveLendingPool);
            _validateAaveRewardsController(aaveRewardsController);

            _populateAaveV2Array();

            data = new bytes[](aaveStrategyParams.length);

            for (uint256 i = 0; i < aaveStrategyParams.length; i++) {
                _validateErc20(aaveStrategyParams[i].tokenIn);
                _validateAaveToken(aaveStrategyParams[i].tokenOut);

                data[i] = abi.encodeCall(
                    AaveV3StrategyV2.initialize,
                    AaveV3StrategyV2.InitializerParams({
                        owner: owner,
                        manager: manager,
                        stakerFactory: stakerFactory,
                        lendingPool: aaveLendingPool,
                        rewardsController: aaveRewardsController,
                        jigsawRewardToken: jigsawRewardToken,
                        rewardToken: aaveStrategyParams[i].rewardToken,
                        jigsawRewardDuration: aaveStrategyParams[i].jigsawRewardDuration,
                        tokenIn: aaveStrategyParams[i].tokenIn,
                        tokenOut: aaveStrategyParams[i].tokenOut
                    })
                );
            }

            return data;
        }

        if (keccak256(bytes(_strategy)) == PENDLE_STRATEGY) {
            string memory pendleConfig = vm.readFile("./deployment-config/02_PendleStrategyConfig.json");
            address pendleRouter = pendleConfig.readAddress(".PENDLE_ROUTER");

            _validatePendleRouter(pendleRouter);

            _populatePendleArray();

            data = new bytes[](pendleStrategyParams.length);
            for (uint256 i = 0; i < pendleStrategyParams.length; i++) {
                _validatePendleMarket(pendleStrategyParams[i].pendleMarket);
                _validateErc20(pendleStrategyParams[i].tokenIn);
                _validateErc20(pendleStrategyParams[i].rewardToken);

                data[i] = abi.encodeCall(
                    PendleStrategy.initialize,
                    PendleStrategy.InitializerParams({
                        owner: owner,
                        manager: manager,
                        stakerFactory: stakerFactory,
                        jigsawRewardToken: jigsawRewardToken,
                        pendleRouter: pendleRouter,
                        pendleMarket: pendleStrategyParams[i].pendleMarket,
                        jigsawRewardDuration: pendleStrategyParams[i].jigsawRewardDuration,
                        tokenIn: pendleStrategyParams[i].tokenIn,
                        tokenOut: pendleStrategyParams[i].pendleMarket,
                        rewardToken: pendleStrategyParams[i].rewardToken
                    })
                );
            }

            return data;
        }

        if (keccak256(bytes(_strategy)) == RESERVOIR_STRATEGY) {
            _populateReservoirSavingStrategy();

            data = new bytes[](reservoirSavingStrategyParams.length);
            for (uint256 i = 0; i < reservoirSavingStrategyParams.length; i++) {
                _validateCreditEnforcer(reservoirSavingStrategyParams[i].creditEnforcer);
                _validatePegStabilityModule(reservoirSavingStrategyParams[i].pegStabilityModule);
                _validateSavingModule(reservoirSavingStrategyParams[i].savingModule);
                _validateErc20(reservoirSavingStrategyParams[i].tokenIn);
                _validateRusd(reservoirSavingStrategyParams[i].rUSD, reservoirSavingStrategyParams[i].savingModule);
                _validateSrUsd(reservoirSavingStrategyParams[i].tokenOut, reservoirSavingStrategyParams[i].savingModule);

                data[i] = abi.encodeCall(
                    ReservoirSavingStrategy.initialize,
                    ReservoirSavingStrategy.InitializerParams({
                        owner: owner,
                        manager: manager,
                        stakerFactory: stakerFactory,
                        jigsawRewardToken: jigsawRewardToken,
                        creditEnforcer: reservoirSavingStrategyParams[i].creditEnforcer,
                        pegStabilityModule: reservoirSavingStrategyParams[i].pegStabilityModule,
                        savingModule: reservoirSavingStrategyParams[i].savingModule,
                        rUSD: reservoirSavingStrategyParams[i].rUSD,
                        jigsawRewardDuration: reservoirSavingStrategyParams[i].jigsawRewardDuration,
                        tokenIn: reservoirSavingStrategyParams[i].tokenIn,
                        tokenOut: reservoirSavingStrategyParams[i].tokenOut
                    })
                );
            }

            return data;
        }

        if (keccak256(bytes(_strategy)) == DINERO_STRATEGY) {
            _populateDineroArray();

            data = new bytes[](dineroStrategyParams.length);
            for (uint256 i = 0; i < dineroStrategyParams.length; i++) {
                _validateErc20(dineroStrategyParams[i].tokenIn);
                _validatePirexEth(dineroStrategyParams[i].pirexEth);
                _validateAutoPirexEth(dineroStrategyParams[i].autoPirexEth);

                data[i] = abi.encodeCall(
                    DineroStrategy.initialize,
                    DineroStrategy.InitializerParams({
                        owner: owner,
                        manager: manager,
                        stakerFactory: stakerFactory,
                        jigsawRewardToken: jigsawRewardToken,
                        pirexEth: dineroStrategyParams[i].pirexEth,
                        autoPirexEth: dineroStrategyParams[i].autoPirexEth,
                        jigsawRewardDuration: dineroStrategyParams[i].jigsawRewardDuration,
                        tokenIn: dineroStrategyParams[i].tokenIn,
                        tokenOut: dineroStrategyParams[i].tokenOut
                    })
                );
            }

            return data;
        }

        if (keccak256(bytes(_strategy)) == ELIXIR_STRATEGY) {
            string memory elixirConfig = vm.readFile("./deployment-config/03_ElixirStrategyConfig.json");
            address uniswapRouter = elixirConfig.readAddress(".UNISWAP_ROUTER");

            _validateUniswapRouter(uniswapRouter);

            _populateElixirArray();

            data = new bytes[](elixirStrategyParams.length);
            for (uint256 i = 0; i < elixirStrategyParams.length; i++) {
                _validateErc20(elixirStrategyParams[i].tokenIn);

                data[i] = abi.encodeCall(
                    ElixirStrategy.initialize,
                    ElixirStrategy.InitializerParams({
                        owner: owner,
                        manager: manager,
                        stakerFactory: stakerFactory,
                        jigsawRewardToken: jigsawRewardToken,
                        feeManager: feeManager,
                        uniswapRouter: uniswapRouter,
                        jigsawRewardDuration: elixirStrategyParams[i].jigsawRewardDuration,
                        tokenIn: elixirStrategyParams[i].tokenIn,
                        tokenOut: elixirStrategyParams[i].tokenOut,
                        deUSD: elixirStrategyParams[i].deUSD,
                        initialPools: elixirStrategyParams[i].initialPools,
                        swapDirections: elixirStrategyParams[i].swapDirections,
                        swapPaths: elixirStrategyParams[i].swapPaths
                    })
                );
            }

            return data;
        }
        revert("Unknown strategy");
    }

    function _populateAaveArray() internal { }

    function _populateAaveV2Array() internal {
        // Populate the individual initialization params per each Aave strategy
        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x29219dd400f2Bf60E5a23d13Be72B486D4038894, //USDC
                tokenOut: 0x578Ee1ca3a8E1b54554Da1Bf7C583506C4CD11c6
            })
        );
    }

    function _populateReservoirSavingStrategy() internal { }

    function _populateDineroArray() internal { }

    function _populatePendleArray() internal { }

    function _populateElixirArray() internal { }
}
