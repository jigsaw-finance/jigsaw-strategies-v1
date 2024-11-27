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
    ) internal returns (bytes memory) {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");

        if (keccak256(bytes(_strategy)) == keccak256(bytes("AaveV3Strategy"))) { }

        if (keccak256(bytes(_strategy)) == keccak256(bytes("IonStrategy"))) {
            string memory ionConfig = vm.readFile("./deployment-config/01_IonStrategyConfig.json");
            return abi.encodeCall(
                IonStrategy.initialize,
                IonStrategy.InitializerParams({
                    owner: commonConfig.readAddress(".INITIAL_OWNER"),
                    managerContainer: commonConfig.readAddress(".MANAGER_CONTAINER"),
                    stakerFactory: commonConfig.readAddress(".STAKER_FACTORY"),
                    ionPool: ionConfig.readAddress(".ION_POOL"),
                    jigsawRewardToken: commonConfig.readAddress(".JIGSAW_REWARDS"),
                    jigsawRewardDuration: ionConfig.readUint(".REWARD_DURATION"),
                    tokenIn: ionConfig.readAddress(".TOKEN_IN"),
                    tokenOut: ionConfig.readAddress(".TOKEN_OUT")
                })
            );
        }

        if (keccak256(bytes(_strategy)) == keccak256(bytes("PendleStrategy"))) { }

        if (keccak256(bytes(_strategy)) == keccak256(bytes("ReservoirStablecoinStrategy"))) { }

        revert("Unknown strategy");
    }
}
