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

import { IonStrategy } from "../../src/ion/IonStrategy.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";
import { IStakerLight } from "../../src/staker/interfaces/IStakerLight.sol";

IIonPool constant ION_POOL = IIonPool(0x0000000000eaEbd95dAfcA37A39fd09745739b78);

contract DeployIonTest is Test, CommonStrategyScriptBase, BasicContractsFixture {
    using StdJson for string;

    DeployProxy internal proxyDeployer;
    IonStrategy internal strategy;

    function setUp() public {
        init();

        DeployImpl implDeployer = new DeployImpl();
        address implementation = implDeployer.run("IonStrategy");

        proxyDeployer = new DeployProxy();
        address[] memory strategies = proxyDeployer.run({
            _strategy: "IonStrategy",
            _implementation: implementation,
            _salt: 0x3412d07bef5d0dcdb942ac1765d0b8f19d8ca2c4cc7a66b902ba9b1ebc080040
        });
        strategy = IonStrategy(strategies[0]);
    }

    function test_ion_initialValues() public {
        string memory commonConfig = vm.readFile("./deployment-config/00_CommonConfig.json");
        address ownerFromConfig = commonConfig.readAddress(".INITIAL_OWNER");
        address managerContainerFromConfig = commonConfig.readAddress(".MANAGER_CONTAINER");
        address jigsawRewardTokenFromConfig = commonConfig.readAddress(".JIGSAW_REWARDS");

        for (uint256 i = 0; i < ionStrategyParams.length; i++) {
            IStakerLight staker = strategy.jigsawStaker();

            _populateIonArray();

            assertEq(strategy.owner(), ownerFromConfig, "Owner initialized wrong");
            assertEq(address(strategy.managerContainer()), managerContainerFromConfig, "ManagerContainer init wrong");
            assertEq(address(strategy.ionPool()), ionStrategyParams[i].ionPool, "Ion Pool initialized wrong");
            assertEq(strategy.tokenIn(), ionStrategyParams[i].tokenIn, "tokenIn initialized wrong");
            assertEq(strategy.tokenOut(), ionStrategyParams[i].tokenOut, "tokenOut initialized wrong");
            assertEq(staker.rewardToken(), jigsawRewardTokenFromConfig, "JigsawRewardToken initialized wrong");
            assertEq(staker.rewardsDuration(), ionStrategyParams[i].jigsawRewardDuration, "RewardsDuration init wrong");
        }
    }
}

interface IIonPool {
    function withdraw(address receiverOfUnderlying, uint256 amount) external;
    function supply(address user, uint256 amount, bytes32[] calldata proof) external;
    function owner() external returns (address);
    function whitelist() external returns (address);
    function updateSupplyCap(
        uint256 newSupplyCap
    ) external;
    function updateIlkDebtCeiling(uint8 ilkIndex, uint256 newCeiling) external;
    function balanceOf(
        address user
    ) external view returns (uint256);
    function normalizedBalanceOf(
        address user
    ) external returns (uint256);
    function totalSupply() external view returns (uint256);
    function debt() external view returns (uint256);
    function supplyFactorUnaccrued() external view returns (uint256);
    function getIlkAddress(
        uint256 ilkIndex
    ) external view returns (address);
    function decimals() external view returns (uint8);
    function balanceOfUnaccrued(
        address user
    ) external view returns (uint256);
}
