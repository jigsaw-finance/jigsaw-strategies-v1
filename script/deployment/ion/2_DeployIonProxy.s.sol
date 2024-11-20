// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { console } from "forge-std/console.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

import { IonStrategy } from "../../../src/ion/IonStrategy.sol";

import { CommonStrategyScriptBase } from "../../CommonStrategyScriptBase.sol";

contract DeployIonProxy is CommonStrategyScriptBase {
    function run(
        address _implementation,
        bytes32 _salt,
        address _ionPool,
        uint256 _rewardDuration,
        address _tokenIn,
        address _tokenOut
    ) external broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY")) returns (address proxy) {
        proxy = address(
            new ERC1967Proxy{ salt: _salt }(
                _implementation,
                abi.encodeCall(
                    IonStrategy.initialize,
                    IonStrategy.InitializerParams({
                        owner: OWNER,
                        managerContainer: MANAGER_CONTAINER,
                        stakerFactory: STAKER_FACTORY,
                        ionPool: _ionPool,
                        jigsawRewardToken: jREWARDS,
                        jigsawRewardDuration: _rewardDuration,
                        tokenIn: _tokenIn,
                        tokenOut: _tokenOut
                    })
                )
            )
        );
    }
}
