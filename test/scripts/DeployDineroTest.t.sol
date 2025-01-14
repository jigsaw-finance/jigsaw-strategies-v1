// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { stdJson as StdJson } from "forge-std/StdJson.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../script/CommonStrategyScriptBase.sol";
import "../fixtures/BasicContractsFixture.t.sol";

import { DeployStakerFactory } from "script/0_DeployStakerFactory.s.sol";
import { DeployImpl } from "script/1_DeployImpl.s.sol";
import { DeployProxy } from "script/2_DeployProxy.s.sol";

import { IStakerLight } from "../../src/staker/interfaces/IStakerLight.sol";

contract DeployDineroTest is Test, CommonStrategyScriptBase, BasicContractsFixture {
    using StdJson for string;

    DeployProxy internal proxyDeployer;
    address[] internal strategies;

    function setUp() public {
        init();

        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("DineroStrategy");

        proxyDeployer = new DeployProxy();
        strategies = proxyDeployer.run({
            _strategy: "DineroStrategy",
            _implementation: implementation,
            _salt: 0x3412d07bef5d0dcdb942ac1765d0b8f19d8ca2c4cc7a66b902ba9b1ebc080040
        });
    }

    function test_dinero_initialValues() public {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");
        address ownerFromConfig = commonConfig.readAddress(".INITIAL_OWNER");
        address managerContainerFromConfig = commonConfig.readAddress(".MANAGER_CONTAINER");
        address jigsawRewardTokenFromConfig = commonConfig.readAddress(".JIGSAW_REWARDS");

        _populateDineroArray();

        for (uint256 i = 0; i < dineroStrategyParams.length; i++) {
            DineroStrategy strategy = DineroStrategy(payable(strategies[i]));
            IStakerLight staker = strategy.jigsawStaker();

            assertEq(strategy.owner(), ownerFromConfig, "Owner initialized wrong");
            assertEq(address(strategy.managerContainer()), managerContainerFromConfig, "ManagerContainer wrong");
            assertEq(address(strategy.pirexEth()), dineroStrategyParams[i].pirexEth, "PirexEth wrong");
            assertEq(address(strategy.autoPirexEth()), dineroStrategyParams[i].autoPirexEth, "autoPirexEth wrong");
            assertEq(strategy.tokenIn(), dineroStrategyParams[i].tokenIn, "tokenIn initialized wrong");
            assertEq(strategy.tokenOut(), dineroStrategyParams[i].tokenOut, "tokenOut initialized wrong");
            assertEq(staker.rewardToken(), jigsawRewardTokenFromConfig, "JigsawRewardToken initialized wrong");
            assertEq(staker.rewardsDuration(), dineroStrategyParams[i].jigsawRewardDuration, "RewardsDuration wrong");
        }
    }
}
