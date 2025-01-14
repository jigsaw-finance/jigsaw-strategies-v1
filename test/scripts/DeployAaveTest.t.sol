// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "../../script/CommonStrategyScriptBase.sol";
import "../fixtures/BasicContractsFixture.t.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { IAToken } from "@aave/v3-core/interfaces/IAToken.sol";
import { IPool } from "@aave/v3-core/interfaces/IPool.sol";
import { IRewardsController } from "@aave/v3-periphery/rewards/interfaces/IRewardsController.sol";

import { DeployImpl } from "script/1_DeployImpl.s.sol";
import { DeployProxy } from "script/2_DeployProxy.s.sol";

import { IStakerLight } from "../../src/staker/interfaces/IStakerLight.sol";

contract DeployAaveTest is Test, CommonStrategyScriptBase, BasicContractsFixture {
    using StdJson for string;

    DeployProxy internal proxyDeployer;
    address[] internal strategies;

    function setUp() public {
        init();

        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("AaveV3Strategy");

        proxyDeployer = new DeployProxy();
        strategies = proxyDeployer.run({
            _strategy: "AaveV3Strategy",
            _implementation: implementation,
            _salt: 0x3412d07bef5d0dcdb942ac1765d0b8f19d8ca2c4cc7a66b902ba9b1ebc080040
        });
    }

    // Test initialization
    function test_initialization() public {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");
        address ownerFromConfig = commonConfig.readAddress(".INITIAL_OWNER");
        address managerContainerFromConfig = commonConfig.readAddress(".MANAGER_CONTAINER");
        address jigsawRewardTokenFromConfig = commonConfig.readAddress(".JIGSAW_REWARDS");

        string memory aaveConfig = vm.readFile("./deployment-config/01_AaveV3StrategyConfig.json");
        address aaveLendingPoolFromConfig = aaveConfig.readAddress(".LENDING_POOL");
        address aaveRewardsControllerFromConfig = aaveConfig.readAddress(".REWARDS_CONTROLLER");

        _populateAaveArray();

        for (uint256 i = 0; i < aaveStrategyParams.length; i++) {
            AaveV3Strategy strategy = AaveV3Strategy(strategies[i]);
            IStakerLight staker = strategy.jigsawStaker();

            assertEq(strategy.owner(), ownerFromConfig, "Owner initialized wrong");
            assertEq(address(strategy.managerContainer()), managerContainerFromConfig, "ManagerContainer  wrong");
            assertEq(address(strategy.lendingPool()), aaveLendingPoolFromConfig, "Lending Pool initialized wrong");
            assertEq(address(strategy.rewardsController()), aaveRewardsControllerFromConfig, "RewardsController wrong");
            assertEq(strategy.tokenIn(), aaveStrategyParams[i].tokenIn, "tokenIn initialized wrong");
            assertEq(strategy.tokenOut(), aaveStrategyParams[i].tokenOut, "tokenOut initialized wrong");
            assertEq(strategy.rewardToken(), aaveStrategyParams[i].rewardToken, "AaveRewardToken wrong");
            assertEq(staker.rewardToken(), jigsawRewardTokenFromConfig, "JigsawRewardToken initialized wrong");
            assertEq(staker.rewardsDuration(), aaveStrategyParams[i].jigsawRewardDuration, "RewardsDuration init wrong");
        }
    }
}
