// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "../fixtures/BasicContractsFixture.t.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";

contract StakerLightTest is Test, BasicContractsFixture {
    address internal STRATEGY = address(uint160(uint256(keccak256("STRATEGY"))));
    address internal tokenIn;

    StakerLight internal staker;
    StakerLightFactory internal factory;

    function setUp() public {
        init();
        tokenIn = address(usdc);

        factory = new StakerLightFactory({ _initialOwner: OWNER, _referenceImplementation: address(new StakerLight()) });

        address deployment = factory.createStakerLight({
            _initialOwner: OWNER,
            _holdingManager: address(holdingManager),
            _rewardToken: jRewards,
            _strategy: STRATEGY,
            _rewardsDuration: 10 days
        });

        staker = StakerLight(deployment);
    }

    function test_when_noRewards(address _user, uint256 _amount) public notOwnerNotZero(_user) {
        _amount = bound(_amount, 1, 1e30);
        address userHolding = initiateUser(_user, tokenIn, _amount);

        vm.startPrank(STRATEGY, STRATEGY);
        staker.deposit(userHolding, _amount);
        vm.assertEq(staker.balanceOf(userHolding), _amount);

        uint256 withdrawalAmount = bound(_amount, 1, _amount);
        staker.withdraw(userHolding, withdrawalAmount);
        vm.assertEq(staker.balanceOf(userHolding), _amount - withdrawalAmount);
        vm.stopPrank();
    }
}
