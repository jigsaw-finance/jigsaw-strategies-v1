// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { console } from "forge-std/console.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

import "../CommonStrategyScriptBase.sol";

contract DeployProxy is CommonStrategyScriptBase {
    using StdJson for string;

    function run(
        string calldata _strategy,
        address _implementation,
        bytes32 _salt
    ) external broadcast returns (address proxy) {
        proxy = address(new ERC1967Proxy{ salt: _salt }(_implementation, _buildProxyData(_strategy)));
    }
}
