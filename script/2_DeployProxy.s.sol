// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./CommonStrategyScriptBase.sol";

contract DeployProxy is CommonStrategyScriptBase {
    function run(
        string calldata _strategy,
        address _implementation,
        bytes32 _salt
    ) external broadcast returns (address[] memory proxies) {
        bytes[] memory proxyData = _buildProxyData(_strategy);
        proxies = new address[](proxyData.length);
        for (uint256 i = 0; i < proxyData.length; i++) {
            proxies[i] =
                address(new ERC1967Proxy{ salt: _salt }({ implementation: _implementation, _data: proxyData[i] }));
        }
    }
}
