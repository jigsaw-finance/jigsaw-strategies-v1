// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "./CommonStrategyScriptBase.s.sol";

import { StakerLight } from "../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../src/staker/StakerLightFactory.sol";

/**
 * @title DeployStakerFactory
 * @notice Script to deploy the `StakerLight` implementation and `StakerLightFactory` contract
 * @dev Inherits from `CommonStrategyScriptBase` to utilize common utilities and helpers
 */
contract DeployStakerFactory is CommonStrategyScriptBase {
    using StdJson for string;

    /**
     * @notice Deploys the `StakerLight` implementation and `StakerLightFactory` contract
     * @dev Reads the initial owner address from the JSON configuration file.
     * @return stakerImplementation The address of the deployed `StakerLight` implementation
     * @return stakerFactory The address of the deployed `StakerLightFactory` contract
     */
    function run() external broadcast returns (address stakerImplementation, address stakerFactory) {
        // Read the common configuration file containing deployment parameters
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");

        // Deploy StakerLight implementation
        stakerImplementation = address(new StakerLight());

        // Deploy StakerFactory contract
        stakerFactory = address(
            new StakerLightFactory({
                _initialOwner: commonConfig.readAddress(".INITIAL_OWNER"),
                _referenceImplementation: address(stakerImplementation)
            })
        );

        return (stakerImplementation, stakerFactory);
    }
}
