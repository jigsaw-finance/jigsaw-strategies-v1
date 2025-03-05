// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./CommonStrategyScriptBase.s.sol";

contract DeployProxy is CommonStrategyScriptBase {
    using StdJson for string;

    function run(
        string calldata _strategy
    ) external broadcast returns (address[] memory proxies) {
        string memory deployments = vm.readFile("./deployments.json");
        bytes[] memory proxyData = _buildProxyData(_strategy);
        proxies = new address[](proxyData.length);

        for (uint256 i = 0; i < proxyData.length; i++) {
            proxies[i] = address(
                new ERC1967Proxy({
                    implementation: deployments.readAddress(string.concat(".", _strategy, "_IMPL")),
                    _data: proxyData[i]
                })
            );
        }
    }
}
