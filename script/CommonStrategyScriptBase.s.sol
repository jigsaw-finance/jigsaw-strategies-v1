// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Script, stdJson as StdJson } from "forge-std/Script.sol";

import { AaveV3Strategy } from "../src/aave/AaveV3Strategy.sol";
import { DineroStrategy } from "../src/dinero/DineroStrategy.sol";
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

    uint256 constant DEFAULT_REWARDS_DURATION = 75 days;

    bytes32 constant AAVE_STRATEGY = keccak256("AaveV3Strategy");
    bytes32 constant PENDLE_STRATEGY = keccak256("PendleStrategy");
    bytes32 constant RESERVOIR_STRATEGY = keccak256("ReservoirSavingStrategy");
    bytes32 constant DINERO_STRATEGY = keccak256("DineroStrategy");

    bytes32 constant AAVE_STRATEGY_V2 = keccak256("AaveV3StrategyV2");
    bytes32 constant PENDLE_STRATEGY_V2 = keccak256("PendleStrategyV2");
    bytes32 constant RESERVOIR_STRATEGY_V2 = keccak256("ReservoirSavingStrategyV2");
    bytes32 constant DINERO_STRATEGY_V2 = keccak256("DineroStrategyV2");

    AaveStrategyParams[] internal aaveStrategyParams;
    PendleStrategyParams[] internal pendleStrategyParams;
    ReservoirSavingStrategyParams[] internal reservoirSavingStrategyParams;
    DineroStrategyParams[] internal dineroStrategyParams;

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

        revert("Unknown strategy");
    }

    function _populateAaveArray() internal {
        // Populate the individual initialization params per each Aave strategy
        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, //USDC
                tokenOut: 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c
            })
        );

        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xdAC17F958D2ee523a2206206994597C13D831ec7, //USDT
                tokenOut: 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a
            })
        );

        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, //wBTC
                tokenOut: 0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8
            })
        );

        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, //wETH
                tokenOut: 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8
            })
        );

        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, //wstETH
                tokenOut: 0x0B925eD163218f6662a35e0f0371Ac234f9E9371
            })
        );

        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee, //weETH
                tokenOut: 0xBdfa7b7893081B35Fb54027489e2Bc7A38275129
            })
        );
    }

    function _populateReservoirSavingStrategy() internal {
        // Populate the initialization params for the ReservoirSavingStrategy, e.g.:
        reservoirSavingStrategyParams.push(
            ReservoirSavingStrategyParams({
                creditEnforcer: 0x04716DB62C085D9e08050fcF6F7D775A03d07720,
                pegStabilityModule: 0x4809010926aec940b550D34a46A52739f996D75D,
                savingModule: 0x5475611Dffb8ef4d697Ae39df9395513b6E947d7,
                rUSD: 0x09D4214C03D01F49544C0448DBE3A27f768F2b34,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x09D4214C03D01F49544C0448DBE3A27f768F2b34, // rUSD as tokenIn
                tokenOut: 0x738d1115B90efa71AE468F1287fc864775e23a31 // srUSD as tokenOut
             })
        );

        reservoirSavingStrategyParams.push(
            ReservoirSavingStrategyParams({
                creditEnforcer: 0x04716DB62C085D9e08050fcF6F7D775A03d07720,
                pegStabilityModule: 0x4809010926aec940b550D34a46A52739f996D75D,
                savingModule: 0x5475611Dffb8ef4d697Ae39df9395513b6E947d7,
                rUSD: 0x09D4214C03D01F49544C0448DBE3A27f768F2b34,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC as tokenIn
                tokenOut: 0x738d1115B90efa71AE468F1287fc864775e23a31 // srUSD as tokenOut
             })
        );
    }

    function _populateDineroArray() internal {
        // Populate the initialization params for the DineroStrategy, e.g.:
        dineroStrategyParams.push(
            DineroStrategyParams({
                pirexEth: 0xD664b74274DfEB538d9baC494F3a4760828B02b0,
                autoPirexEth: 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, //wETH
                tokenOut: 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6
            })
        );
    }

    function _populatePendleArray() internal {
        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0x048680F64d6DFf1748ba6D9a01F578433787e24B,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0, // USD0++
                rewardToken: 0x808507121B80c02388fAd14726482e061B8da827
            })
        );
    }
}
