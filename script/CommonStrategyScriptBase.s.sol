// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Script, stdJson as StdJson } from "forge-std/Script.sol";

import { AaveV3Strategy } from "../src/aave/AaveV3Strategy.sol";
import { DineroStrategy } from "../src/dinero/DineroStrategy.sol";
import { IonStrategy } from "../src/ion/IonStrategy.sol";
import { PendleStrategy } from "../src/pendle/PendleStrategy.sol";
import { ReservoirStablecoinStrategy } from "../src/reservoir/ReservoirStablecoinStrategy.sol";

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
    }

    struct PendleStrategyParams {
        address pendleMarket; // The address of the Pendle's Market contract.
        uint256 jigsawRewardDuration; // the duration of the jigsaw rewards (jPoints) distribution;
        address tokenIn; // The address of the LP token
        address rewardToken; // The address of the Pendle primary reward token
    }

    struct ReservoirStablecoinStrategyParams {
        address creditEnforcer; // The address of the Reservoir's CreditEnforcer contract
        address pegStabilityModule; // The Reservoir's PegStabilityModule contract.
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
    bytes32 constant ION_STRATEGY = keccak256("IonStrategy");
    bytes32 constant PENDLE_STRATEGY = keccak256("PendleStrategy");
    bytes32 constant RESERVOIR_STRATEGY = keccak256("ReservoirStablecoinStrategy");
    bytes32 constant DINERO_STRATEGY = keccak256("DineroStrategy");

    AaveStrategyParams[] internal aaveStrategyParams;
    IonStrategyParams[] internal ionStrategyParams;
    PendleStrategyParams[] internal pendleStrategyParams;
    ReservoirStablecoinStrategyParams[] internal reservoirStablecoinStrategyParams;
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
                        tokenOut: ionStrategyParams[i].ionPool
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
                        tokenOut: pendleStrategyParams[i].pendleMarket,
                        rewardToken: pendleStrategyParams[i].rewardToken
                    })
                );
            }

            return data;
        }

        if (keccak256(bytes(_strategy)) == RESERVOIR_STRATEGY) {
            _populateReservoirStablecoinStrategy();

            data = new bytes[](1);
            data[0] = abi.encodeCall(
                ReservoirStablecoinStrategy.initialize,
                ReservoirStablecoinStrategy.InitializerParams({
                    owner: owner,
                    managerContainer: managerContainer,
                    stakerFactory: stakerFactory,
                    jigsawRewardToken: jigsawRewardToken,
                    creditEnforcer: reservoirStablecoinStrategyParams[0].creditEnforcer,
                    pegStabilityModule: reservoirStablecoinStrategyParams[0].pegStabilityModule,
                    jigsawRewardDuration: reservoirStablecoinStrategyParams[0].jigsawRewardDuration,
                    tokenIn: reservoirStablecoinStrategyParams[0].tokenIn,
                    tokenOut: reservoirStablecoinStrategyParams[0].tokenOut
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
                tokenIn: 0xdAC17F958D2ee523a2206206994597C13D831ec7, //USDT
                tokenOut: 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a
            })
        );

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
                tokenIn: 0x6B175474E89094C44Da98b954EedeAC495271d0F, //DAI
                tokenOut: 0x018008bfb33d285247A21d44E50697654f754e63
            })
        );

        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497, //sUSDe
                tokenOut: 0x4579a27aF00A62C0EB156349f31B345c08386419
            })
        );
    }

    function _populateIonArray() internal {
        // Populate the individual initialization params per each Ion strategy, e.g.:
        ionStrategyParams.push(
            IonStrategyParams({
                ionPool: 0x0000000000eaEbd95dAfcA37A39fd09745739b78, //wstETH/weETH Ion Pool
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
            })
        );

        ionStrategyParams.push(
            IonStrategyParams({
                ionPool: 0x00000000007C8105548f9d0eE081987378a6bE93, //wstETH/rswETH Ion Pool
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
            })
        );

        ionStrategyParams.push(
            IonStrategyParams({
                ionPool: 0x0000000000E33e35EE6052fae87bfcFac61b1da9, //wstETH/rsETH Ion Pool
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
            })
        );

        ionStrategyParams.push(
            IonStrategyParams({
                ionPool: 0x00000000008a3A77bd91bC738Ed2Efaa262c3763, //wETH/ezETH Ion Pool
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
            })
        );
    }

    function _populateReservoirStablecoinStrategy() internal {
        // Populate the initialization params for the ReservoirStablecoinStrategy, e.g.:
        reservoirStablecoinStrategyParams.push(
            ReservoirStablecoinStrategyParams({
                creditEnforcer: 0x04716DB62C085D9e08050fcF6F7D775A03d07720,
                pegStabilityModule: 0x4809010926aec940b550D34a46A52739f996D75D,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, //USDC
                tokenOut: 0x09D4214C03D01F49544C0448DBE3A27f768F2b34
            })
        );
    }

    function _populatePendleArray() internal {
        // Populate the individual initialization params per each Pendle strategy, e.g.:
        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0xB162B764044697cf03617C2EFbcB1f42e31E4766,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497, // sUSDe
                rewardToken: 0x808507121B80c02388fAd14726482e061B8da827
            })
        );

        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0x048680F64d6DFf1748ba6D9a01F578433787e24B,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0, // USD0++
                rewardToken: 0x808507121B80c02388fAd14726482e061B8da827
            })
        );

        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0xfd5Cf95E8b886aCE955057cA4DC69466e793FBBE,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0, // rswETH
                rewardToken: 0x808507121B80c02388fAd14726482e061B8da827
            })
        );

        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0x58612beB0e8a126735b19BB222cbC7fC2C162D2a,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xD9A442856C234a39a81a089C06451EBAa4306a72, // pufETH
                rewardToken: 0x808507121B80c02388fAd14726482e061B8da827
            })
        );

        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0x931F7eA0c31c14914a452d341bc5Cb5d996BE71d,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x8236a87084f8B84306f72007F36F2618A5634494, // LBTC
                rewardToken: 0x808507121B80c02388fAd14726482e061B8da827
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
}
