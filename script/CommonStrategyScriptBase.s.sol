// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Script, stdJson as StdJson } from "forge-std/Script.sol";

import { AaveV3Strategy } from "../src/aave/AaveV3Strategy.sol";
import { DineroStrategy } from "../src/dinero/DineroStrategy.sol";
import { IonStrategy } from "../src/ion/IonStrategy.sol";
import { PendleStrategy } from "../src/pendle/PendleStrategy.sol";
import { ReservoirSavingStrategy } from "../src/reservoir/ReservoirSavingStrategy.sol";

contract CommonStrategyScriptBase is Script {
    using StdJson for string;

    struct AaveStrategyParams {
        address rewardToken; // Aave reward token used in the integrated pool;
        uint256 jigsawRewardDuration; // the duration of the jigsaw rewards (jPoints) distribution;
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of the Aave receipt token (aToken)
    }

    struct IonStrategyParams {
        address ionPool; // Ion pool used for strategy;
        uint256 jigsawRewardDuration; // the duration of the jigsaw rewards (jPoints) distribution;
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of the Ion receipt token (iToken)
    }

    struct PendleStrategyParams {
        address pendleMarket; // The address of the Pendle's Market contract.
        uint256 jigsawRewardDuration; // the duration of the jigsaw rewards (jPoints) distribution;
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of the Pendle receipt token
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

    bytes32 constant AAVE_STRATEGY = keccak256("AaveV3Strategy");
    bytes32 constant ION_STRATEGY = keccak256("IonStrategy");
    bytes32 constant PENDLE_STRATEGY = keccak256("PendleStrategy");
    bytes32 constant RESERVOIR_STRATEGY = keccak256("ReservoirSavingStrategy");
    bytes32 constant DINERO_STRATEGY = keccak256("DineroStrategy");

    AaveStrategyParams[] internal aaveStrategyParams;
    IonStrategyParams[] internal ionStrategyParams;
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
        address managerContainer = commonConfig.readAddress(".MANAGER_CONTAINER");
        address jigsawRewardToken = commonConfig.readAddress(".JIGSAW_REWARDS");
        address stakerFactory = deployments.readAddress(".STAKER_FACTORY");

        if (keccak256(bytes(_strategy)) == AAVE_STRATEGY) {
            string memory aaveConfig = vm.readFile("./deployment-config/01_AaveV3StrategyConfig.json");
            address aaveLendingPool = aaveConfig.readAddress(".LENDING_POOL");
            address aaveRewardsController = aaveConfig.readAddress(".REWARDS_CONTROLLER");

            _populateAaveArray();

            data = new bytes[](aaveStrategyParams.length);

            for (uint256 i = 0; i < aaveStrategyParams.length; i++) {
                data[i] = abi.encodeCall(
                    AaveV3Strategy.initialize,
                    AaveV3Strategy.InitializerParams({
                        owner: owner,
                        managerContainer: managerContainer,
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

        if (keccak256(bytes(_strategy)) == ION_STRATEGY) {
            _populateIonArray();

            data = new bytes[](ionStrategyParams.length);

            for (uint256 i = 0; i < ionStrategyParams.length; i++) {
                data[i] = abi.encodeCall(
                    IonStrategy.initialize,
                    IonStrategy.InitializerParams({
                        owner: owner,
                        managerContainer: managerContainer,
                        stakerFactory: stakerFactory,
                        jigsawRewardToken: jigsawRewardToken,
                        ionPool: ionStrategyParams[i].ionPool,
                        jigsawRewardDuration: ionStrategyParams[i].jigsawRewardDuration,
                        tokenIn: ionStrategyParams[i].tokenIn,
                        tokenOut: ionStrategyParams[i].tokenOut
                    })
                );
            }

            return data;
        }

        if (keccak256(bytes(_strategy)) == PENDLE_STRATEGY) {
            string memory pendleConfig = vm.readFile("./deployment-config/02_PendleStrategyConfig.json");
            address pendleRouter = pendleConfig.readAddress(".PENDLE_ROUTER");

            _populatePendleArray();

            data = new bytes[](pendleStrategyParams.length);

            for (uint256 i = 0; i < pendleStrategyParams.length; i++) {
                data[i] = abi.encodeCall(
                    PendleStrategy.initialize,
                    PendleStrategy.InitializerParams({
                        owner: owner,
                        managerContainer: managerContainer,
                        stakerFactory: stakerFactory,
                        jigsawRewardToken: jigsawRewardToken,
                        pendleRouter: pendleRouter,
                        pendleMarket: pendleStrategyParams[i].pendleMarket,
                        jigsawRewardDuration: pendleStrategyParams[i].jigsawRewardDuration,
                        tokenIn: pendleStrategyParams[i].tokenIn,
                        tokenOut: pendleStrategyParams[i].tokenOut,
                        rewardToken: pendleStrategyParams[i].rewardToken
                    })
                );
            }

            return data;
        }

        if (keccak256(bytes(_strategy)) == RESERVOIR_STRATEGY) {
            _populateReservoirSavingStrategy();

            data = new bytes[](1);
            data[0] = abi.encodeCall(
                ReservoirSavingStrategy.initialize,
                ReservoirSavingStrategy.InitializerParams({
                    owner: owner,
                    managerContainer: managerContainer,
                    stakerFactory: stakerFactory,
                    jigsawRewardToken: jigsawRewardToken,
                    creditEnforcer: reservoirSavingStrategyParams[0].creditEnforcer,
                    pegStabilityModule: reservoirSavingStrategyParams[0].pegStabilityModule,
                    savingModule: reservoirSavingStrategyParams[0].savingModule,
                    rUSD: reservoirSavingStrategyParams[0].rUSD,
                    jigsawRewardDuration: reservoirSavingStrategyParams[0].jigsawRewardDuration,
                    tokenIn: reservoirSavingStrategyParams[0].tokenIn,
                    tokenOut: reservoirSavingStrategyParams[0].tokenOut
                })
            );

            return data;
        }

        if (keccak256(bytes(_strategy)) == DINERO_STRATEGY) {
            _populateDineroArray();

            data = new bytes[](1);
            data[0] = abi.encodeCall(
                DineroStrategy.initialize,
                DineroStrategy.InitializerParams({
                    owner: owner,
                    managerContainer: managerContainer,
                    stakerFactory: stakerFactory,
                    jigsawRewardToken: jigsawRewardToken,
                    pirexEth: dineroStrategyParams[0].pirexEth,
                    autoPirexEth: dineroStrategyParams[0].autoPirexEth,
                    jigsawRewardDuration: dineroStrategyParams[0].jigsawRewardDuration,
                    tokenIn: dineroStrategyParams[0].tokenIn,
                    tokenOut: dineroStrategyParams[0].tokenOut
                })
            );

            return data;
        }

        revert("Unknown strategy");
    }

    function _populateAaveArray() internal {
        // Populate the individual initialization params per each Aave strategy, e.g.:
        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: 365 days,
                tokenIn: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                tokenOut: 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c
            })
        );
    }

    function _populateIonArray() internal {
        // Populate the individual initialization params per each Ion strategy, e.g.:
        ionStrategyParams.push(
            IonStrategyParams({
                ionPool: 0x0000000000eaEbd95dAfcA37A39fd09745739b78,
                jigsawRewardDuration: 365 days,
                tokenIn: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                tokenOut: 0x0000000000eaEbd95dAfcA37A39fd09745739b78
            })
        );
    }

    function _populatePendleArray() internal {
        // Populate the individual initialization params per each Pendle strategy, e.g.:
        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0x676106576004EF54B4bD39Ce8d2B34069F86eb8f,
                jigsawRewardDuration: 365 days,
                tokenIn: 0xD9A442856C234a39a81a089C06451EBAa4306a72,
                tokenOut: 0x676106576004EF54B4bD39Ce8d2B34069F86eb8f,
                rewardToken: 0x808507121B80c02388fAd14726482e061B8da827
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
                jigsawRewardDuration: 365 days,
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
                jigsawRewardDuration: 365 days,
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
                jigsawRewardDuration: 365 days,
                tokenIn: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                tokenOut: 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6
            })
        );
    }
}
