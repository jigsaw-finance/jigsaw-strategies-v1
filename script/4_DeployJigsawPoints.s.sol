// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "./CommonStrategyScriptBase.s.sol";

import { JigsawPoints } from "../src/jPoints/JigsawPoints.sol";

/**
 * @title DeployJigsawPoints
 * @notice Script to deploy the JigsawPoints contract for Jigsaw Protocol
 * @dev Inherits from CommonStrategyScriptBase to utilize common utilities and helpers
 */
contract DeployJigsawPoints is CommonStrategyScriptBase {
    using StdJson for string;

    /**
     * @notice Deploys the JigsawPoints contract.
     * @dev Reads the initial owner address from the JSON configuration file.
     * @return jPoints The address of the deployed JigsawPoints contract.
     */
    function run() external broadcast returns (address jPoints) {
        // Read the common configuration file containing deployment parameters
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");

        // Deploy JigsawPoints contract
        jPoints =
            address(new JigsawPoints({ _initialAdmin: commonConfig.readAddress(".INITIAL_OWNER"), _premintAmount: 0 }));
    }
}
