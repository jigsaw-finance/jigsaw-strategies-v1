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

contract DeployReservoirTest is Test, CommonStrategyScriptBase, BasicContractsFixture {
    using StdJson for string;

    DeployProxy internal proxyDeployer;
    address[] internal strategies;

    function setUp() public {
        init();

        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("ReservoirStablecoinStrategy");

        // Save implementation address to deployments
        Strings.toHexString(uint160(implementation), 20).write(
            "./deployments.json", ".ReservoirStablecoinStrategy_IMPL"
        );

        proxyDeployer = new DeployProxy();
        strategies = proxyDeployer.run({ _strategy: "ReservoirStablecoinStrategy" });
    }

    function test_reservoir_initialValues() public {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");
        address ownerFromConfig = commonConfig.readAddress(".INITIAL_OWNER");
        address managerContainerFromConfig = commonConfig.readAddress(".MANAGER_CONTAINER");
        address jigsawRewardTokenFromConfig = commonConfig.readAddress(".JIGSAW_REWARDS");

        _populateReservoirStablecoinStrategy();

        for (uint256 i = 0; i < reservoirStablecoinStrategyParams.length; i++) {
            ReservoirStablecoinStrategy strategy = ReservoirStablecoinStrategy(strategies[i]);
            IStakerLight staker = strategy.jigsawStaker();

            assertEq(strategy.owner(), ownerFromConfig, "Owner initialized wrong");
            assertEq(address(strategy.managerContainer()), managerContainerFromConfig, "ManagerContainer wrong");
            assertEq(
                address(strategy.pegStabilityModule()),
                reservoirStablecoinStrategyParams[i].pegStabilityModule,
                "PegStabilityModule wrong"
            );
            assertEq(
                address(strategy.creditEnforcer()),
                reservoirStablecoinStrategyParams[i].creditEnforcer,
                "CreditEnforcer wrong"
            );
            assertEq(strategy.tokenIn(), reservoirStablecoinStrategyParams[i].tokenIn, "tokenIn initialized wrong");
            assertEq(strategy.tokenOut(), reservoirStablecoinStrategyParams[i].tokenOut, "tokenOut initialized wrong");
            assertEq(staker.rewardToken(), jigsawRewardTokenFromConfig, "JigsawRewardToken initialized wrong");
            assertEq(
                staker.rewardsDuration(),
                reservoirStablecoinStrategyParams[i].jigsawRewardDuration,
                "RewardsDuration wrong"
            );
        }
    }
}
