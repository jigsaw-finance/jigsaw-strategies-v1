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

contract DeployPendleTest is Test, CommonStrategyScriptBase, BasicContractsFixture {
    using StdJson for string;

    DeployProxy internal proxyDeployer;
    address[] internal strategies;

    function setUp() public {
        init();

        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("PendleStrategy");

        proxyDeployer = new DeployProxy();
        strategies = proxyDeployer.run({
            _strategy: "PendleStrategy",
            _implementation: implementation,
            _salt: 0x3412d07bef5d0dcdb942ac1765d0b8f19d8ca2c4cc7a66b902ba9b1ebc080040
        });
    }

    function test_pendle_initialValues() public {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");
        address ownerFromConfig = commonConfig.readAddress(".INITIAL_OWNER");
        address managerContainerFromConfig = commonConfig.readAddress(".MANAGER_CONTAINER");
        address jigsawRewardTokenFromConfig = commonConfig.readAddress(".JIGSAW_REWARDS");

        string memory pendleConfig = vm.readFile("./deployment-config/02_PendleStrategyConfig.json");
        address pendleRouter = pendleConfig.readAddress(".PENDLE_ROUTER");

        _populatePendleArray();

        for (uint256 i = 0; i < pendleStrategyParams.length; i++) {
            PendleStrategy strategy = PendleStrategy(strategies[i]);
            IStakerLight staker = strategy.jigsawStaker();

            assertEq(strategy.owner(), ownerFromConfig, "Owner initialized wrong");
            assertEq(address(strategy.managerContainer()), managerContainerFromConfig, "ManagerContainer wrong");
            assertEq(address(strategy.pendleRouter()), pendleRouter, "PendleRouter wrong");
            assertEq(address(strategy.pendleMarket()), pendleStrategyParams[i].pendleMarket, "PendleRouter wrong");
            assertEq(address(strategy.rewardToken()), pendleStrategyParams[i].rewardToken, "PendleRouter wrong");
            assertEq(strategy.tokenIn(), pendleStrategyParams[i].tokenIn, "tokenIn initialized wrong");
            assertEq(strategy.tokenOut(), pendleStrategyParams[i].tokenOut, "tokenOut initialized wrong");
            assertEq(staker.rewardToken(), jigsawRewardTokenFromConfig, "JigsawRewardToken initialized wrong");
            assertEq(staker.rewardsDuration(), pendleStrategyParams[i].jigsawRewardDuration, "RewardsDuration wrong");
        }
    }
}
