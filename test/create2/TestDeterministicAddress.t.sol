// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { IonStrategy } from "../../src/ion/IonStrategy.sol";

contract TestDeterministicAddress is StdInvariant, Test {
    address internal deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 initCodeHash = keccak256(type(IonStrategy).creationCode);

    function test_deterministic() public {
        address deployment;
        bytes32 salt;

        console.logBytes32(initCodeHash);

        for (uint256 i = 0; i < 10_000_000_000; ++i) {
            // bytes32 tempSalt = keccak256(abi.encode(i));
            bytes32 tempSalt = bytes32(i);

            address tempDeployment =
                vm.computeCreate2Address({ salt: tempSalt, initCodeHash: initCodeHash, deployer: deployer });

            // Check if the first four bytes are zero
            if (uint160(tempDeployment) >> (160 - 16) == 0) {
                salt = tempSalt;
                deployment = tempDeployment;
                break;
            }
        }

        if (deployment == address(0)) revert("Address not found");

        console.logBytes32(salt);
        console.log("Address:", deployment);
    }

    function test_predefined_salt() public {
        bytes32 predefined_salt = 0x00000000000000000000000000000000000000000000000000000000014b9245;
        address tempDeployment =
            vm.computeCreate2Address({ salt: predefined_salt, initCodeHash: initCodeHash, deployer: deployer });

        console.log("Address", tempDeployment);
    }
}
