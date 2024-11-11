// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";

import { DeployStaker } from "script/deployment/0_DeployStaker.s.sol";

contract DeployStakerTest is Test, BasicContractsFixture {
    DeployStaker internal stakerDeployer;

    function setUp() public {
        init();

        stakerDeployer = new DeployStaker();

        console.log("OWNER", OWNER);
        console.log("CONT", address(managerContainer));
        console.log("REWARDS", address(jRewards));
    }

    function test_deployStaker() public {
        stakerDeployer.run();
    }
}
