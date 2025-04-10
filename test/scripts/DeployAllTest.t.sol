// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "../../script/CommonStrategyScriptBase.s.sol";
import "../fixtures/BasicContractsFixture.t.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { IAToken } from "@aave/v3-core/interfaces/IAToken.sol";
import { IPool } from "@aave/v3-core/interfaces/IPool.sol";
import { IRewardsController } from "@aave/v3-periphery/rewards/interfaces/IRewardsController.sol";

import { DeployStakerFactory } from "script/0_DeployStakerFactory.s.sol";
import { DeployImpl } from "script/1_DeployImpl.s.sol";
import { DeployProxy } from "script/2_DeployProxy.s.sol";

import { IStakerLight } from "../../src/staker/interfaces/IStakerLight.sol";

contract DeployAllTest is Test, CommonStrategyScriptBase, BasicContractsFixture {
    using StdJson for string;

    DeployProxy internal proxyDeployer;
    address ownerFromConfig;
    address managerFromConfig;
    address jigsawRewardTokenFromConfig;
    address[] internal strategies;

    function setUp() public {
        init();

        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");

        ownerFromConfig = commonConfig.readAddress(".INITIAL_OWNER");
        managerFromConfig = commonConfig.readAddress(".MANAGER");
        jigsawRewardTokenFromConfig = commonConfig.readAddress(".JIGSAW_REWARDS");
    }

    function test_all_initializations() public {
        aave_initialization();
        dinero_initialization();
        pendle_initialization();
        reservoir_initialization();
    }

    function aave_initialization() public {
        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("AaveV3Strategy");

        // Save implementation address to deployments
        Strings.toHexString(uint160(implementation), 20).write("./deployments.json", ".AaveV3Strategy_IMPL");

        proxyDeployer = new DeployProxy();
        strategies = proxyDeployer.run({ _strategy: "AaveV3Strategy" });

        string memory aaveConfig = vm.readFile("./deployment-config/01_AaveV3StrategyConfig.json");
        address aaveLendingPoolFromConfig = aaveConfig.readAddress(".LENDING_POOL");
        address aaveRewardsControllerFromConfig = aaveConfig.readAddress(".REWARDS_CONTROLLER");

        _populateAaveArray();

        for (uint256 i = 0; i < aaveStrategyParams.length; i++) {
            AaveV3Strategy strategy = AaveV3Strategy(strategies[i]);
            IStakerLight staker = strategy.jigsawStaker();

            assertEq(strategy.owner(), ownerFromConfig, "Owner initialized wrong");
            assertEq(address(strategy.manager()), managerFromConfig, "ManagerContainer  wrong");
            assertEq(address(strategy.lendingPool()), aaveLendingPoolFromConfig, "Lending Pool initialized wrong");
            assertEq(address(strategy.rewardsController()), aaveRewardsControllerFromConfig, "RewardsController wrong");
            assertEq(strategy.tokenIn(), aaveStrategyParams[i].tokenIn, "tokenIn initialized wrong");
            assertEq(strategy.tokenOut(), aaveStrategyParams[i].tokenOut, "tokenOut initialized wrong");
            assertEq(strategy.rewardToken(), aaveStrategyParams[i].rewardToken, "AaveRewardToken wrong");
            assertEq(staker.rewardToken(), jigsawRewardTokenFromConfig, "JigsawRewardToken initialized wrong");
            assertEq(staker.rewardsDuration(), aaveStrategyParams[i].jigsawRewardDuration, "RewardsDuration init wrong");
        }
    }

    function dinero_initialization() public {
        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("DineroStrategy");

        // Save implementation address to deployments
        Strings.toHexString(uint160(implementation), 20).write("./deployments.json", ".DineroStrategy_IMPL");

        proxyDeployer = new DeployProxy();
        strategies = proxyDeployer.run({ _strategy: "DineroStrategy" });

        _populateDineroArray();

        for (uint256 i = 0; i < dineroStrategyParams.length; i++) {
            DineroStrategy strategy = DineroStrategy(payable(strategies[i]));
            IStakerLight staker = strategy.jigsawStaker();

            assertEq(strategy.owner(), ownerFromConfig, "Owner initialized wrong");
            assertEq(address(strategy.manager()), managerFromConfig, "ManagerContainer wrong");
            assertEq(address(strategy.pirexEth()), dineroStrategyParams[i].pirexEth, "PirexEth wrong");
            assertEq(address(strategy.autoPirexEth()), dineroStrategyParams[i].autoPirexEth, "autoPirexEth wrong");
            assertEq(strategy.tokenIn(), dineroStrategyParams[i].tokenIn, "tokenIn initialized wrong");
            assertEq(strategy.tokenOut(), dineroStrategyParams[i].tokenOut, "tokenOut initialized wrong");
            assertEq(staker.rewardToken(), jigsawRewardTokenFromConfig, "JigsawRewardToken initialized wrong");
            assertEq(staker.rewardsDuration(), dineroStrategyParams[i].jigsawRewardDuration, "RewardsDuration wrong");
        }
    }

    function pendle_initialization() public {
        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("PendleStrategy");

        // Save implementation address to deployments
        Strings.toHexString(uint160(implementation), 20).write("./deployments.json", ".PendleStrategy_IMPL");

        proxyDeployer = new DeployProxy();
        strategies = proxyDeployer.run({ _strategy: "PendleStrategy" });

        string memory pendleConfig = vm.readFile("./deployment-config/02_PendleStrategyConfig.json");
        address pendleRouter = pendleConfig.readAddress(".PENDLE_ROUTER");

        _populatePendleArray();

        for (uint256 i = 0; i < pendleStrategyParams.length; i++) {
            PendleStrategy strategy = PendleStrategy(strategies[i]);
            IStakerLight staker = strategy.jigsawStaker();

            assertEq(strategy.owner(), ownerFromConfig, "Owner initialized wrong");
            assertEq(address(strategy.manager()), managerFromConfig, "ManagerContainer wrong");
            assertEq(address(strategy.pendleRouter()), pendleRouter, "PendleRouter wrong");
            assertEq(address(strategy.pendleMarket()), pendleStrategyParams[i].pendleMarket, "PendleRouter wrong");
            assertEq(address(strategy.rewardToken()), pendleStrategyParams[i].rewardToken, "PendleRouter wrong");
            assertEq(strategy.tokenIn(), pendleStrategyParams[i].tokenIn, "tokenIn initialized wrong");
            assertEq(strategy.tokenOut(), pendleStrategyParams[i].pendleMarket, "tokenOut initialized wrong");
            assertEq(staker.rewardToken(), jigsawRewardTokenFromConfig, "JigsawRewardToken initialized wrong");
            assertEq(staker.rewardsDuration(), pendleStrategyParams[i].jigsawRewardDuration, "RewardsDuration wrong");
        }
    }

    function reservoir_initialization() public {
        init();

        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("ReservoirSavingStrategy");

        // Save implementation address to deployments
        Strings.toHexString(uint160(implementation), 20).write("./deployments.json", ".ReservoirSavingStrategy_IMPL");

        proxyDeployer = new DeployProxy();
        strategies = proxyDeployer.run({ _strategy: "ReservoirSavingStrategy" });

        _populateReservoirSavingStrategy();

        for (uint256 i = 0; i < reservoirSavingStrategyParams.length; i++) {
            ReservoirSavingStrategy strategy = ReservoirSavingStrategy(strategies[i]);
            IStakerLight staker = strategy.jigsawStaker();

            assertEq(strategy.owner(), ownerFromConfig, "Owner initialized wrong");
            assertEq(address(strategy.manager()), managerFromConfig, "ManagerContainer wrong");
            assertEq(
                address(strategy.pegStabilityModule()),
                reservoirSavingStrategyParams[i].pegStabilityModule,
                "PegStabilityModule wrong"
            );
            assertEq(
                address(strategy.creditEnforcer()),
                reservoirSavingStrategyParams[i].creditEnforcer,
                "CreditEnforcer wrong"
            );
            assertEq(
                address(strategy.savingModule()), reservoirSavingStrategyParams[i].savingModule, "SavingModule wrong"
            );
            assertEq(address(strategy.rUSD()), reservoirSavingStrategyParams[i].rUSD, "rUSD wrong");
            assertEq(strategy.tokenIn(), reservoirSavingStrategyParams[i].tokenIn, "tokenIn initialized wrong");
            assertEq(strategy.tokenOut(), reservoirSavingStrategyParams[i].tokenOut, "tokenOut initialized wrong");
            assertEq(staker.rewardToken(), jigsawRewardTokenFromConfig, "JigsawRewardToken initialized wrong");
            assertEq(
                staker.rewardsDuration(), reservoirSavingStrategyParams[i].jigsawRewardDuration, "RewardsDuration wrong"
            );
        }
    }

    function test_deployStaker() public {
        DeployStakerFactory stakerDeployer;
        address staker;
        address factory;

        stakerDeployer = new DeployStakerFactory();
        (staker, factory) = stakerDeployer.run();

        vm.assertEq(StakerLightFactory(factory).owner(), OWNER, "Owner in factory is wrong");
        vm.assertEq(
            StakerLightFactory(factory).referenceImplementation(), staker, "ReferenceImplementation in factory wrong"
        );
    }
}
