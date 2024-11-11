// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Options } from "openzeppelin-foundry-upgrades/Options.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { IonStrategy } from "../../src/ion/IonStrategy.sol";

import { CommonStrategyScriptBase } from "../CommonStrategyScriptBase.sol";

contract DeployIonStrategy is CommonStrategyScriptBase {
    function run(
        address _ionPool,
        uint256 _rewardDuration,
        address _tokenIn,
        address _tokenOut
    ) external returns (address proxy) {
        Options memory opts;
        opts.unsafeAllow = "constructor";

        bytes memory initializerData = abi.encodeCall(
            IonStrategy.initialize,
            IonStrategy.InitializerParams({
                owner: OWNER,
                managerContainer: MANAGER_CONTAINER,
                stakerFactory: STAKER_FACTORY,
                ionPool: _ionPool,
                jigsawRewardToken: jREWARDS,
                jigsawRewardDuration: _rewardDuration,
                tokenIn: _tokenIn,
                tokenOut: _tokenOut
            })
        );

        vm.broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        // Deploy UUPS upgradeable IonStrategy contract using OZ's Upgrades plugin
        proxy = Upgrades.deployUUPSProxy({
            contractName: "out/IonStrategy.sol/IonStrategy.json",
            initializerData: initializerData,
            opts: opts
        });
    }
}
