// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "./CommonStrategyScriptBase.sol";

import { StakerLight } from "../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../src/staker/StakerLightFactory.sol";

contract DeployStakerFactory is CommonStrategyScriptBase {
    using StdJson for string;

    function run() external broadcast returns (address, address) {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");

        // Deploy StakerLight implementation
        StakerLight stakerImplementation = new StakerLight();
        // Deploy StakerFactory contract
        StakerLightFactory stakerFactory = new StakerLightFactory({
            _initialOwner: commonConfig.readAddress(".INITIAL_OWNER"),
            _referenceImplementation: address(stakerImplementation)
        });

        return (address(stakerImplementation), address(stakerFactory));
    }
}
