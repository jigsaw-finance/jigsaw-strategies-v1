// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../fixtures/BasicContractsFixture.t.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ReservoirStablecoinStrategy } from "../../src/reservoir/ReservoirStablecoinStrategy.sol";
import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";

address constant RESERVOIR_CI = 0x04716DB62C085D9e08050fcF6F7D775A03d07720;
address constant RESERVOIR_PSM = 0x4809010926aec940b550D34a46A52739f996D75D;

contract ReservoirStablecoinStrategyTest is Test, BasicContractsFixture {
    // Mainnet USDC
    address internal tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Reservoir stablecoin (rUSD)
    address internal tokenOut = 0x09D4214C03D01F49544C0448DBE3A27f768F2b34;

    ReservoirStablecoinStrategy internal strategy;

    function setUp() public {
        init();

        address jRewards = address(new ERC20Mock());
        address stakerFactory = address(new StakerLightFactory({ _initialOwner: OWNER }));
        address strategyImplementation = address(new ReservoirStablecoinStrategy());
        bytes memory data = abi.encodeCall(
            ReservoirStablecoinStrategy.initialize,
            ReservoirStablecoinStrategy.InitializerParams({
                owner: OWNER,
                managerContainer: address(managerContainer),
                creditEnforcer: RESERVOIR_CI,
                pegStabilityModule: RESERVOIR_PSM,
                stakerFactory: stakerFactory,
                jigsawRewardToken: jRewards,
                jigsawRewardDuration: 60 days,
                tokenIn: tokenIn,
                tokenOut: tokenOut
            })
        );

        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = ReservoirStablecoinStrategy(proxy);

        // Add tested strategy to the StrategyManager for integration testing purposes
        vm.startPrank((OWNER));
        manager.whitelistToken(tokenIn);
        strategyManager.addStrategy(address(strategy));

        SharesRegistry tokenInSharesRegistry = new SharesRegistry(
            OWNER, address(managerContainer), address(tokenIn), address(usdcOracle), bytes(""), 50_000
        );
        stablesManager.registerOrUpdateShareRegistry(address(tokenInSharesRegistry), address(tokenIn), true);
        registries[address(tokenIn)] = address(tokenInSharesRegistry);
        vm.stopPrank();
    }

    // Tests if deposit works correctly when authorized
    function test_reservoir_deposit_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 100_000e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(userHolding);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) = strategyManager.invest(tokenIn, address(strategy), amount, "");

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(userHolding);
        uint256 expectedShares = balanceAfter - balanceBefore;

        (uint256 investedAmount, uint256 totalShares) = strategy.recipients(userHolding);

        assertApproxEqRel(
            balanceAfter, balanceBefore + amount * 10 ** 12, 0.01e18, "Wrong balance in Reservoir after mint"
        );
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
        assertEq(investedAmount, amount, "Recipient invested amount mismatch");
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");
    }

    // Tests if withdrawal works correctly when authorized
    function test_reservoir_claimInvestment_when_authorized(
        address user,
        uint256 _amount
    ) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 100_000e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, "");

        (, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 withdrawalShares = bound(totalShares, 1, totalShares);
        uint256 underlyingBefore = IERC20(tokenIn).balanceOf(userHolding);

        // withdraw partially
        vm.prank(user, user);
        strategyManager.claimInvestment(userHolding, address(strategy), withdrawalShares, tokenIn, "");

        uint256 underlyingAfter = IERC20(tokenIn).balanceOf(userHolding);
        (, uint256 updatedShares) = strategy.recipients(userHolding);

        assertEq(underlyingAfter - underlyingBefore, withdrawalShares / 1e12, "Withdrawn wrong amount");
        assertEq(totalShares - withdrawalShares, updatedShares, "Shares amount updated wrong");

        // withdraw the rest
        vm.prank(user, user);
        strategyManager.claimInvestment(userHolding, address(strategy), totalShares - withdrawalShares, tokenIn, "");
        (, uint256 finalShares) = strategy.recipients(userHolding);

        assertEq(IERC20(tokenIn).balanceOf(userHolding), totalShares / 1e12, "Withdrawn wrong amount");
        assertEq(IERC20(tokenOut).balanceOf(userHolding), 0, "Wrong rUSD  amount");
        assertEq(finalShares, 0, "Shares amount updated wrong");
    }
}
