// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "../fixtures/BasicContractsFixture.t.sol";
import "../fixtures/StrategyTestUtils.t.sol";

import { AaveV3Strategy } from "../../src/aave/AaveV3Strategy.sol";
import { AaveV3StrategyV2 } from "../../src/aave/AaveV3StrategyV2.sol";

import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";
import { IAToken } from "@aave/v3-core/interfaces/IAToken.sol";
import { IPool } from "@aave/v3-core/interfaces/IPool.sol";
import { IRewardsController } from "@aave/v3-periphery/rewards/interfaces/IRewardsController.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AaveV3StrategyV2UpgradeTest is Test, BasicContractsFixture, StrategyTestUtils {
    AaveV3Strategy internal strategy;

    address internal lendingPool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal rewardsController = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address internal emissionManager = 0x223d844fc4B006D67c0cDbd39371A9F73f69d974;

    // Mainnet usdc
    address internal tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Aave interest bearing aUSDC
    address internal tokenOut = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        strategy = AaveV3Strategy(0x05329BbE8b9DEcf80A09ee84998250e6B137Bda2);
        feeManager = FeeManager(0x552DD7F539D5480a2714DF8ED066D67264A4544C);
    }

    // Tests if withdraw works correctly for v2
    function test_withdraw_aave_v2_reinitialize() public {
        vm.startPrank(strategy.owner(), strategy.owner());

        // Deploy the new implementation of AaveV3StrategyV2
        address strategyV2Implementation = address(new AaveV3StrategyV2());

        // Perform the upgrade
        bytes memory data = abi.encodeCall(
            AaveV3StrategyV2.reinitialize, AaveV3StrategyV2.ReinitializerParams({ feeManager: address(feeManager) })
        );

        strategy.upgradeToAndCall(strategyV2Implementation, data);
        vm.stopPrank();

        assertEq(address(feeManager), address(AaveV3StrategyV2(address(strategy)).feeManager()));

        FeeManager(address(AaveV3StrategyV2(address(strategy)).feeManager())).getHoldingFee(
            address(89_278), address(strategy)
        );

        // 0xfaa4fd1500000000000000000000000066930f2122c5f09112b4237c49efdf03e227487c
        // 0x66930f2122C5f09112b4237C49EfDF03E227487C
    }

    // Upgrade AaveV3Strategy to AaveV3StrategyV2
    function _upgradeToV2() internal override {
        vm.startPrank(OWNER, OWNER);

        // Deploy the new implementation of AaveV3StrategyV2
        address strategyV2Implementation = address(new AaveV3StrategyV2());

        // Perform the upgrade
        bytes memory data = abi.encodeCall(
            AaveV3StrategyV2.reinitialize, AaveV3StrategyV2.ReinitializerParams({ feeManager: address(feeManager) })
        );

        strategy.upgradeToAndCall(strategyV2Implementation, data);
        vm.stopPrank();
    }

    function _getStrategyStateVariables() internal view override returns (StrategyStateVariables memory) {
        return StrategyStateVariables({
            owner: strategy.owner(),
            manager: address(strategy.manager()),
            rewardToken: strategy.rewardToken(),
            tokenIn: strategy.tokenIn(),
            tokenOut: strategy.tokenOut(),
            sharesDecimals: strategy.sharesDecimals()
        });
    }
}
