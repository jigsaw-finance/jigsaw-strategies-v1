// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { IonStrategy } from "../../src/ion/IonStrategy.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestDeterministicAddress is StdInvariant, Test {
    address internal deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 initCodeHash = keccak256(type(IonStrategy).creationCode);

    function test_deterministic() public view {
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

    function test_predefined_salt() public view {
        bytes32 predefined_salt = 0x00000000000000000000000000000000000000000000000000000000014b9245;
        address tempDeployment =
            vm.computeCreate2Address({ salt: predefined_salt, initCodeHash: initCodeHash, deployer: deployer });

        console.log("Address", tempDeployment);
    }

    function test_predefined_salt_proxy() public view {
        bytes32 proxyCodeHash = keccak256(
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    0x833fb4cAb68407B55C9177fB8BF62BA51CBc22cB,
                    abi.encodeCall(
                        IonStrategy.initialize,
                        IonStrategy.InitializerParams({
                            owner: 0x3412d07beF5d0DcDb942aC1765D0b8f19D8CA2C4,
                            manager: 0xB23B5406c67b31DB4BC223afa20fc75ebBa50CA9,
                            stakerFactory: 0xE41fCFCe505457DB0DF31aD6D3D20606D8Fb1c6E,
                            ionPool: 0x0000000000eaEbd95dAfcA37A39fd09745739b78,
                            jigsawRewardToken: 0x371BC93e9661d445fC046918231483faDF1Dbd96,
                            jigsawRewardDuration: 5_184_000,
                            tokenIn: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
                        })
                    )
                )
            )
        );

        address tempDeployment = vm.computeCreate2Address({
            salt: 0x3412d07bef5d0dcdb942ac1765d0b8f19d8ca2c4ef3c940d196ed2af33000018,
            initCodeHash: proxyCodeHash
        });
        console.log("Address", tempDeployment);
    }
}
