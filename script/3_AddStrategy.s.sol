// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { StrategyManager } from "@jigsaw/src/StrategyManager.sol";

import "./CommonStrategyScriptBase.sol";
import { Script, console2 as console } from "forge-std/Script.sol";

contract AddStrategy is CommonStrategyScriptBase {
    using StdJson for string;

    function run(
        address _strategy
    ) external broadcastFrom(vm.envUint("OWNER_PRIVATE_KEY")) {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");
        address strategyManager = commonConfig.readAddress(".STRATEGY_MANAGER");
        StrategyManager(strategyManager).addStrategy(_strategy);
    }
}
