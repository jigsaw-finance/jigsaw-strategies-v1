// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { CommonStrategyScriptBase } from "../CommonStrategyScriptBase.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";

contract DeployStaker is CommonStrategyScriptBase {
    function run()
        external
        broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"))
        returns (StakerLight stakerImplementation, StakerLightFactory stakerFactory)
    {
        // Deploy StakerLight implementation
        stakerImplementation = new StakerLight();
        // Deploy StakerFactory contract
        stakerFactory =
            new StakerLightFactory({ _initialOwner: OWNER, _referenceImplementation: address(stakerImplementation) });
    }
}
