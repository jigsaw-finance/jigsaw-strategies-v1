// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Script, stdJson as StdJson } from "forge-std/Script.sol";

import { AaveV3Strategy } from "../src/aave/AaveV3Strategy.sol";
import { DineroStrategy } from "../src/dinero/DineroStrategy.sol";
import { PendleStrategy } from "../src/pendle/PendleStrategy.sol";
import { ReservoirSavingStrategy } from "../src/reservoir/ReservoirSavingStrategy.sol";

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

        revert("Unknown strategy");
    }

    function _populateAaveArray() internal {
        // Populate the individual initialization params per each Aave strategy
        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x29219dd400f2Bf60E5a23d13Be72B486D4038894, //USDC
                tokenOut: 0x578Ee1ca3a8E1b54554Da1Bf7C583506C4CD11c6
            })
        );

        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38, //wS
                tokenOut: 0x6C5E14A212c1C3e4Baf6f871ac9B1a969918c131
            })
        );

        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x50c42dEAcD8Fc9773493ED674b675bE577f2634b, //WETH
                tokenOut: 0xe18Ab82c81E7Eecff32B8A82B1b7d2d23F1EcE96
            })
        );

        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955, //stS
                tokenOut: 0xeAa74D7F42267eB907092AF4Bc700f667EeD0B8B
            })
        );
    }

    function _populatePendleArray() internal {
        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0x3aeF1d372d0a7a7E482F465Bc14A42D78f920392,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955, // stS - until 29 May 2025
                rewardToken: 0xf1eF7d2D4C0c881cd634481e0586ed5d2871A74B
            })
        );

                pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0x004f76045b42ef3e89814b12b37E69da19C8a212,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x9fb76f7ce5FCeAA2C42887ff441D46095E494206, // wstkscUSD - until 18 Dec 2025
                rewardToken: 0xf1eF7d2D4C0c881cd634481e0586ed5d2871A74B
            })
        );

        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0x7e2bcdB749D90Aa1E9E7262872AC8B1e062B2C4D,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0xE8a41c62BB4d5863C6eadC96792cFE90A1f37C47, // wstksceth - until 18 Dec 2025
                rewardToken: 0xf1eF7d2D4C0c881cd634481e0586ed5d2871A74B
            })
        );

        pendleStrategyParams.push(
            PendleStrategyParams({
                pendleMarket: 0xC1fd739f2Bf1Aad96F04d6AE35ED04DA4D68366b,
                jigsawRewardDuration: DEFAULT_REWARDS_DURATION,
                tokenIn: 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1, // wOS - until 18 Dec 2025
                rewardToken: 0xf1eF7d2D4C0c881cd634481e0586ed5d2871A74B
            })
        );
    }
    }

