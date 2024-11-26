// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { console } from "forge-std/console.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

import { IonStrategy } from "../../../src/ion/IonStrategy.sol";

import { CommonStrategyScriptBase } from "../../CommonStrategyScriptBase.sol";

contract DeployIonImpl is CommonStrategyScriptBase {
    function run(
        bytes32 _salt
    ) external broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY")) returns (address implementation) {
        // Deploy implementation
        implementation = address(new IonStrategy{ salt: _salt }());
    }
}
