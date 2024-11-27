// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { console } from "forge-std/console.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

import "../CommonStrategyScriptBase.sol";

contract DeployImpl is CommonStrategyScriptBase {
    /**
     * @notice Deploys the appropriate strategy implementation based on the provided strategy name
     * @param _strategy The strategy name to deploy
     * @return The address of the deployed strategy contract
     */
    function run(
        string memory _strategy
    ) external broadcast returns (address) {
        if (keccak256(bytes(_strategy)) == keccak256(bytes("AaveV3Strategy"))) return address(new AaveV3Strategy());
        if (keccak256(bytes(_strategy)) == keccak256(bytes("IonStrategy"))) return address(new IonStrategy());
        if (keccak256(bytes(_strategy)) == keccak256(bytes("PendleStrategy"))) return address(new PendleStrategy());
        if (keccak256(bytes(_strategy)) == keccak256(bytes("ReservoirStablecoinStrategy"))) {
            return address(new ReservoirStablecoinStrategy());
        }

        revert("Unknown strategy");
    }
}
