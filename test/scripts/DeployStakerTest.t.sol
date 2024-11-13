// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";

import { DeployStaker } from "script/deployment/0_DeployStaker.s.sol";

contract DeployStakerTest is Test, BasicContractsFixture {
    DeployStaker internal stakerDeployer;

    StakerLight internal staker;
    StakerLightFactory internal factory;

    function setUp() public {
        init();
        stakerDeployer = new DeployStaker();
        (staker, factory) = stakerDeployer.run();
    }

    function test_deployStaker() public {
        vm.assertEq(factory.owner(), OWNER, "Owner in factory is wrong");
        vm.assertEq(factory.referenceImplementation(), address(staker), "ReferenceImplementation in factory wrong");
    }
}
