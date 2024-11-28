// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

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

import { AaveV3Strategy } from "../../src/aave/AaveV3Strategy.sol";
import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";
import { IStakerLight } from "../../src/staker/interfaces/IStakerLight.sol";

contract DeployAaveTest is Test, BasicContractsFixture {
    using StdJson for string;

    DeployProxy internal proxyDeployer;
    AaveV3Strategy internal strategy;

    address internal lendingPool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal rewardsController = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address internal emissionManager = 0x223d844fc4B006D67c0cDbd39371A9F73f69d974;
    address internal tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Mainnet usdc
    address internal tokenOut = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c; // Aave interest bearing aUSDC

    function setUp() public {
        init();

        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("AaveV3Strategy");

        proxyDeployer = new DeployProxy();
        strategy = AaveV3Strategy(
            proxyDeployer.run({
                _strategy: "AaveV3Strategy",
                _implementation: implementation,
                _salt: 0x3412d07bef5d0dcdb942ac1765d0b8f19d8ca2c4cc7a66b902ba9b1ebc080040
            })
        );
    }

    // Test initialization
    function test_initialization() public view {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");
        string memory aaveConfig = vm.readFile("./deployment-config/02_AaveV3StrategyConfig.json");

        assertEq(strategy.owner(), commonConfig.readAddress(".INITIAL_OWNER"), "Owner initialized wrong");
        assertEq(
            address(strategy.managerContainer()),
            commonConfig.readAddress(".MANAGER_CONTAINER"),
            "Manager Container initialized wrong"
        );
        assertEq(
            address(strategy.lendingPool()), aaveConfig.readAddress(".LENDING_POOL"), "Lending Pool initialized wrong"
        );
        assertEq(strategy.tokenIn(), aaveConfig.readAddress(".TOKEN_IN"), "tokenIn initialized wrong");
        assertEq(strategy.tokenOut(), aaveConfig.readAddress(".TOKEN_OUT"), "tokenOut initialized wrong");
        assertEq(
            address(strategy.rewardsController()),
            aaveConfig.readAddress(".REWARDS_CONTROLLER"),
            "Wrong rewardsController"
        );
        assertEq(strategy.rewardToken(), aaveConfig.readAddress(".REWARD_TOKEN"), "Wrong rewardToken");

        IStakerLight staker = strategy.jigsawStaker();

        assertEq(staker.rewardToken(), commonConfig.readAddress(".JIGSAW_REWARDS"), "rewardToken initialized wrong");
        assertEq(staker.rewardsDuration(), aaveConfig.readUint(".REWARD_DURATION"), "rewardsDuration initialized wrong");
        assertEq(
            staker.periodFinish(),
            block.timestamp + aaveConfig.readUint(".REWARD_DURATION"),
            "periodFinish initialized wrong"
        );
    }
}
