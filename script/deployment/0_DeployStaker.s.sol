// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { CommonStrategyScriptBase } from "../CommonStrategyScriptBase.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";

contract DeployStaker is CommonStrategyScriptBase {
    function run() external returns (StakerLightFactory stakerFactory, StakerLight stakerImplementation) {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // Deploy StakerFactory contract
        stakerFactory = new StakerLightFactory(OWNER);

        // Deploy StkaerLight implementation
        stakerImplementation = new StakerLight();

        // Set StakerLight implementation in StakerFactory
        stakerFactory.setStakerLightReferenceImplementation(address(stakerImplementation));

        vm.stopBroadcast();
    }
}
