// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";

import { DeployStakerFactory } from "script/deployment/0_DeployStakerFactory.s.sol";

contract DeployStakerFactoryTest is Test, BasicContractsFixture {
    DeployStakerFactory internal stakerDeployer;

    address internal staker;
    address internal factory;

    function setUp() public {
        init();
        stakerDeployer = new DeployStakerFactory();
        (staker, factory) = stakerDeployer.run();
    }

    function test_deployStaker() public {
        vm.assertEq(StakerLightFactory(factory).owner(), OWNER, "Owner in factory is wrong");
        vm.assertEq(
            StakerLightFactory(factory).referenceImplementation(), staker, "ReferenceImplementation in factory wrong"
        );
    }
}
