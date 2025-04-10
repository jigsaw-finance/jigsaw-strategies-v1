// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// -- Jigsaw --

import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";

// -- Aave --
import { IAToken } from "@aave/v3-core/interfaces/IAToken.sol";
import { IPool } from "@aave/v3-core/interfaces/IPool.sol";
import { IRewardsController } from "@aave/v3-periphery/rewards/interfaces/IRewardsController.sol";

// -- Ion --
import { IIonPool } from "../../src/ion/interfaces/IIonPool.sol";

// -- Pendle --
import { IPAllActionV3 } from "@pendle/interfaces/IPAllActionV3.sol";
import { IPMarket } from "@pendle/interfaces/IPMarket.sol";

// -- Reservoir --
import { ICreditEnforcerMin } from "./interfaces/reservoir/ICreditEnforcerMin.sol";
import { IPegStabilityModuleMin } from "./interfaces/reservoir/IPegStabilityModuleMin.sol";
import { ISavingModuleMin } from "./interfaces/reservoir/ISavingModuleMin.sol";

// -- Dinero --
import { IAutoPxEthMin } from "./interfaces/dinero/IAutoPxEthMin.sol";
import { IPirexEthMin } from "./interfaces/dinero/IPirexEthMin.sol";

/**
 * @notice Validates that an address implements the expected interface by checking there is code at the provided address
 * and calling a few functions.
 */
abstract contract ValidateInterface {
    // -- General validation --

    function _validateErc20(
        address tokenAddress
    ) internal view {
        require(tokenAddress.code.length > 0, "Token address must have code");
        IERC20(tokenAddress).balanceOf(address(this));
        IERC20(tokenAddress).totalSupply();
        IERC20(tokenAddress).allowance(address(this), address(this));
    }

    // -- Jigsaw validation --

    function _validateManager(
        address manager
    ) internal view {
        require(manager.code.length > 0, "Manager address must have code");
        IManager(manager).WETH();
        IManager(manager).jUsdOracle();
        IManager(manager).allowedInvokers(address(this));
    }

    function _validateStakerFactory(
        address stakerFactory
    ) internal view {
        require(stakerFactory.code.length > 0, "Staker factory address must have code");
        StakerLightFactory(stakerFactory).referenceImplementation();
        StakerLightFactory(stakerFactory).owner();
    }

    // -- Aave V3 validation --

    function _validateAaveLendingPool(
        address lendingPool
    ) internal view {
        require(lendingPool.code.length > 0, "Lending pool address must have code");
        IPool(lendingPool).getReserveData(address(this));
        IPool(lendingPool).ADDRESSES_PROVIDER();
        IPool(lendingPool).getReservesList();
    }

    function _validateAaveRewardsController(
        address rewardsController
    ) internal view {
        require(rewardsController.code.length > 0, "Rewards controller address must have code");
        IRewardsController(rewardsController).getClaimer(address(this));
        IRewardsController(rewardsController).getTransferStrategy(address(this));
        IRewardsController(rewardsController).getRewardOracle(address(this));
    }

    function _validateAaveToken(
        address token
    ) internal view {
        require(token.code.length > 0, "Token address must have code");
        IAToken(token).UNDERLYING_ASSET_ADDRESS();
        IAToken(token).RESERVE_TREASURY_ADDRESS();
        IAToken(token).DOMAIN_SEPARATOR();
    }

    // -- Ion validation --

    function _validateIonPool(
        address pool
    ) internal view {
        require(pool.code.length > 0, "Pool address must have code");
        IIonPool(pool).balanceOf(address(this));
        IIonPool(pool).normalizedBalanceOf(address(this));
    }

    // -- Pendle validation --

    function _validatePendleRouter(
        address router
    ) internal view {
        require(router.code.length > 0, "Router address must have code");
        IPAllActionV3(router).selectorToFacet(bytes4(keccak256("")));
    }

    function _validatePendleMarket(
        address market
    ) internal view {
        require(market.code.length > 0, "Market address must have code");
        IPMarket(market).expiry();
        IPMarket(market).readTokens();
        IPMarket(market).isExpired();
    }

    // -- Reservoir validation --

    function _validateCreditEnforcer(
        address creditEnforcer
    ) internal view {
        require(creditEnforcer.code.length > 0, "Credit enforcer address must have code");
        ICreditEnforcerMin(creditEnforcer).duration();
        ICreditEnforcerMin(creditEnforcer).smDebtMax();
        ICreditEnforcerMin(creditEnforcer).psmDebtMax();
    }

    function _validatePegStabilityModule(
        address pegStabilityModule
    ) internal view {
        require(pegStabilityModule.code.length > 0, "Peg stability module address must have code");
        IPegStabilityModuleMin(pegStabilityModule).totalValue();
        IPegStabilityModuleMin(pegStabilityModule).totalRiskValue();
        IPegStabilityModuleMin(pegStabilityModule).underlyingBalance();
    }

    function _validateSavingModule(
        address savingModule
    ) internal view {
        require(savingModule.code.length > 0, "Saving module address must have code");
        ISavingModuleMin(savingModule).currentPrice();
        ISavingModuleMin(savingModule).redeemFee();
        ISavingModuleMin(savingModule).rusd();
        ISavingModuleMin(savingModule).srusd();
    }

    function _validateRusd(address rUSD, address savingModule) internal view {
        require(rUSD.code.length > 0, "rUSD address must have code");
        require(
            address(ISavingModuleMin(savingModule).rusd()) == rUSD,
            "rUSD address from savings module must match rUSD address"
        );
    }

    function _validateSrUsd(address srUSD, address savingModule) internal view {
        require(srUSD.code.length > 0, "srUSD address must have code");
        require(
            address(ISavingModuleMin(savingModule).srusd()) == srUSD,
            "srUSD address from savings module must match srUSD address"
        );
    }

    // -- Dinero validation --

    function _validatePirexEth(
        address pirexEth
    ) internal view {
        require(pirexEth.code.length > 0, "Pirex ETH address must have code");
        IPirexEthMin(pirexEth).pxEth();
        IPirexEthMin(pirexEth).pendingDeposit();
        IPirexEthMin(pirexEth).outstandingRedemptions();
    }

    function _validateAutoPirexEth(
        address autoPirexEth
    ) internal view {
        require(autoPirexEth.code.length > 0, "Auto Pirex ETH address must have code");
        IAutoPxEthMin(autoPirexEth).totalAssets();
        IAutoPxEthMin(autoPirexEth).lastTimeRewardApplicable();
        IAutoPxEthMin(autoPirexEth).rewardPerToken();
        IAutoPxEthMin(autoPirexEth).withdrawalPenalty();
    }
}
