// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { Script, stdJson as StdJson } from "forge-std/Script.sol";

import { AaveV3Strategy } from "../src/aave/AaveV3Strategy.sol";
import { IonStrategy } from "../src/ion/IonStrategy.sol";
import { PendleStrategy } from "../src/pendle/PendleStrategy.sol";
import { ReservoirStablecoinStrategy } from "../src/reservoir/ReservoirStablecoinStrategy.sol";

contract CommonStrategyScriptBase is Script {
    using StdJson for string;

    struct AaveStrategyParams {
        address rewardToken; // Aave reward token used in the integrated pool;
        uint256 jigsawRewardDuration; // the duration of the jigsaw rewards (jPoints) distribution;
        address tokenIn; // tokenIn of the Strategy;
        address tokenOut; // tokenOut of the Strategy;
    }

    struct IonStrategyParams {
        address ionPool; // Ion pool used for strategy;
        uint256 jigsawRewardDuration; // the duration of the jigsaw rewards (jPoints) distribution;
        address tokenIn; // tokenIn of the Strategy;
        address tokenOut; // tokenOut of the Strategy;
    }

    AaveStrategyParams[] internal aaveStrategyParams;
    IonStrategyParams[] internal ionStrategyParams;

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

    constructor() {
        // Populate the individual initialization params per each aave strategy, e.g.:
        aaveStrategyParams.push(
            AaveStrategyParams({
                rewardToken: address(0),
                jigsawRewardDuration: 365 days,
                tokenIn: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                tokenOut: 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c
            })
        );

        // Populate the individual initialization params per each ion strategy, e.g.:
        ionStrategyParams.push(
            IonStrategyParams({
                ionPool: 0x0000000000eaEbd95dAfcA37A39fd09745739b78,
                jigsawRewardDuration: 365 days,
                tokenIn: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                tokenOut: 0x0000000000eaEbd95dAfcA37A39fd09745739b78
            })
        );
    }

    function _buildProxyData(
        string calldata _strategy
    ) internal view returns (bytes[] memory data) {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");
        address owner = commonConfig.readAddress(".INITIAL_OWNER");
        address managerContainer = commonConfig.readAddress(".MANAGER_CONTAINER");
        address stakerFactory = commonConfig.readAddress(".STAKER_FACTORY");
        address jigsawRewardToken = commonConfig.readAddress(".JIGSAW_REWARDS");

        if (keccak256(bytes(_strategy)) == keccak256(bytes("AaveV3Strategy"))) {
            string memory aaveConfig = vm.readFile("./deployment-config/01_AaveV3StrategyConfig.json");
            address aaveLendingPool = aaveConfig.readAddress(".LENDING_POOL");
            address aaveRewardsController = aaveConfig.readAddress(".REWARDS_CONTROLLER");

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

        if (keccak256(bytes(_strategy)) == keccak256(bytes("IonStrategy"))) {
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

        // Handle other strategies if needed
        if (keccak256(bytes(_strategy)) == keccak256(bytes("PendleStrategy"))) { }

        if (keccak256(bytes(_strategy)) == keccak256(bytes("ReservoirStablecoinStrategy"))) { }

        revert("Unknown strategy");
    }
}
