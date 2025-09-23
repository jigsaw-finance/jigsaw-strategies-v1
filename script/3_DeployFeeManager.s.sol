// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "./CommonStrategyScriptBase.s.sol";

import { FeeManager } from "../src/extensions/FeeManager.sol";

/**
 * @title DeployFeeManager
 * @notice Script to deploy the FeeManager contract for Jigsaw Protocol
 * @dev Inherits from CommonStrategyScriptBase to utilize common utilities and helpers
 */
contract DeployFeeManager is CommonStrategyScriptBase {
    using StdJson for string;

    /**
     * @notice Deploys the FeeManager contract.
     * @dev Reads the initial owner and manager addresses from the JSON configuration file.
     * @return feeManager The address of the deployed FeeManager contract.
     */
    function run() external broadcast returns (address feeManager) {
        // Read the common configuration file containing deployment parameters
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");

        // Deploy FeeManager contract
        feeManager = address(
            new FeeManager({
                _initialOwner: commonConfig.readAddress(".INITIAL_OWNER"),
                _manager: commonConfig.readAddress(".MANAGER")
            })
        );
    }
}
