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
import { AddStrategy } from "script/3_AddStrategy.s.sol";

import { AaveV3Strategy } from "../../src/aave/AaveV3Strategy.sol";
import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";
import { IStakerLight } from "../../src/staker/interfaces/IStakerLight.sol";

contract AddStrategyTest is Test, BasicContractsFixture {
    using StdJson for string;

    AddStrategy internal strategyAdder;

    function setUp() public {
        init();
        strategyAdder = new AddStrategy();
    }

    // Test initialization
    function test_initialization() public {
        address strategy = address(
            new StrategyWithoutRewardsMock({
                _managerContainer: address(managerContainer),
                _tokenIn: address(usdc),
                _tokenOut: address(usdc),
                _rewardToken: address(0),
                _receiptTokenName: "RUsdc-Mock",
                _receiptTokenSymbol: "RUSDCM"
            })
        );

        strategyAdder.run(strategy);
        (, bool active,) = strategyManager.strategyInfo(strategy);
        assertEq(active, true);
    }
}
