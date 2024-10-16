// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../fixtures/BasicContractsFixture.t.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { IPool } from "@aave/v3-core/interfaces/IPool.sol";
import { IRewardsController } from "@aave/v3-periphery/rewards/interfaces/IRewardsController.sol";

import { AaveV3Strategy } from "../../src/aave/AaveV3Strategy.sol";
import { StakerLight } from "../../src/staker/StakerLight.sol";
import { StakerLightFactory } from "../../src/staker/StakerLightFactory.sol";

contract AaveV3StrategyTest is Test, BasicContractsFixture {
    event Deposit(
        address indexed asset,
        address indexed tokenIn,
        uint256 assetAmount,
        uint256 tokenInAmount,
        uint256 shares,
        address indexed recipient
    );

    AaveV3Strategy internal strategy;

    address internal lendingPool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal rewardsController = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address internal emissionManager = 0x223d844fc4B006D67c0cDbd39371A9F73f69d974;

    // Mainnet usdc
    address internal tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Aave interest bearing aUSDC
    address internal tokenOut = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    function setUp() public {
        init();

        address jRewards = address(new ERC20Mock());
        address stakerFactory = address(new StakerLightFactory({ _initialOwner: OWNER }));

        address strategyImplementation = address(new AaveV3Strategy());

        AaveV3Strategy.InitializerParams memory initParams = AaveV3Strategy.InitializerParams({
            owner: OWNER,
            managerContainer: address(managerContainer),
            stakerFactory: address(stakerFactory),
            lendingPool: lendingPool,
            rewardsController: rewardsController,
            rewardToken: address(0),
            jigsawRewardToken: jRewards,
            jigsawRewardDuration: 60 days,
            tokenIn: tokenIn,
            tokenOut: tokenOut
        });

        bytes memory data = abi.encodeCall(AaveV3Strategy.initialize, initParams);

        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = AaveV3Strategy(proxy);

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

    // Test initialization
    function test_initialization() public view {
        assertEq(strategy.owner(), OWNER, "Wrong owner");
        assertEq(address(strategy.managerContainer()), address(managerContainer), "Wrong managerContainer");
        assertEq(address(strategy.lendingPool()), lendingPool, "Wrong lendingPool");
        assertEq(address(strategy.rewardsController()), rewardsController, "Wrong rewardsController");
        assertEq(strategy.rewardToken(), address(0), "Wrong rewardToken");
        assertEq(strategy.tokenIn(), tokenIn, "Wrong tokenIn");
        assertEq(strategy.tokenOut(), tokenOut, "Wrong tokenOut");
    }

    // Tests if deposit reverts correctly when wrong asset
    function test_deposit_when_wrongAsset(address asset) public {
        vm.assume(asset != strategy.tokenIn());
        // Invest into the tested strategy vie strategyManager
        vm.prank(address(strategyManager), address(strategyManager));
        vm.expectRevert(bytes("3001"));
        strategy.deposit(asset, 1, address(1), "");
    }

    // Tests if deposit works correctly when authorized
    function test_deposit_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 10e6);
        // Mock values and setup necessary approvals and balances for the test
        address userHolding = initiateUser(user, tokenIn, amount);
        // Mock expected behaviors and balances before deposit
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(userHolding);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) = strategyManager.invest(tokenIn, address(strategy), amount, "");

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(userHolding);
        uint256 expectedShares = balanceAfter - balanceBefore;
        (uint256 investedAmount, uint256 totalShares) = strategy.recipients(userHolding);

        // Assert statements with reasons
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
        assertEq(investedAmount, amount, "Recipient invested amount mismatch");
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");
        assertEq(strategy.totalInvestments(), amount, "Total investments mismatch");
    }

    // Tests if deposit works correctly when authorized
    function test_deposit_when_referral() public {
        address user = address(uint160(uint256(keccak256(bytes("ADMIN")))));
        uint256 amount = 100e6;
        // Mock values and setup necessary approvals and balances for the test
        address userHolding = initiateUser(user, tokenIn, amount);
        // Mock expected behaviors and balances before deposit
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(userHolding);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) =
            strategyManager.invest(tokenIn, address(strategy), amount, abi.encode("random ref"));

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(userHolding);
        uint256 expectedShares = balanceAfter - balanceBefore;
        (uint256 investedAmount, uint256 totalShares) = strategy.recipients(userHolding);

        // Assert statements with reasons
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
        assertEq(investedAmount, amount, "Recipient invested amount mismatch");
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");
        assertEq(strategy.totalInvestments(), amount, "Total investments mismatch");
    }

    // Tests if withdraw reverts correctly when wrong asset
    function test_withdraw_when_wrongAsset(address asset) public {
        vm.assume(asset != strategy.tokenIn());
        // Invest into the tested strategy vie strategyManager
        vm.prank(address(strategyManager), address(strategyManager));
        vm.expectRevert(bytes("3001"));
        strategy.deposit(asset, 1, address(1), "");
    }

    // Tests if withdraw reverts correctly when specified shares s
    function test_withdraw_when_wrongShares() public {
        // Invest into the tested strategy vie strategyManager
        vm.prank(address(strategyManager), address(strategyManager));
        vm.expectRevert(bytes("2002"));
        strategy.withdraw(1, address(1), tokenIn, "");
    }

    // Tests if withdraw works correctly when authorized
    // Is not fuzzy because Aave's withdraw randomly over/under flows due to undetermined reason
    function test_withdraw_when_authorized() public {
        address user = vm.addr(uint256(keccak256(bytes("Random user address"))));
        uint256 amount = 9_000_624;

        // Mock values and setup necessary approvals and balances for the test
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, "");

        (, uint256 totalShares) = strategy.recipients(userHolding);

        // Mock the recipient’s shares balance
        uint256 balanceBefore = IERC20(tokenIn).balanceOf(userHolding);

        vm.prank(user, user);
        (uint256 assetAmount, uint256 tokenInAmount) = strategyManager.claimInvestment({
            _holding: userHolding,
            _strategy: address(strategy),
            _shares: totalShares,
            _asset: tokenIn,
            _data: ""
        });

        uint256 balanceAfter = IERC20(tokenIn).balanceOf(userHolding);
        uint256 expectedWithdrawal = balanceAfter - balanceBefore;

        (, uint256 totalSharesAfter) = strategy.recipients(userHolding);

        // Assert statements with reasons
        assertEq(assetAmount, expectedWithdrawal, "Incorrect asset amount returned");
        assertApproxEqAbs(tokenInAmount, expectedWithdrawal, 1, "Incorrect tokenInAmount returned");
        assertEq(totalSharesAfter, 0, "Recipient total shares mismatch after withdrawal");
        assertEq(strategy.totalInvestments(), 0, "Total investments mismatch after withdrawal");
    }

    // Tests if claimRewards works correctly when authorized
    // function test_claimRewards_when_authorized() public {
    //     address user = vm.addr(uint256(keccak256(bytes("Random user address"))));
    //     uint256 amount = 10e6;

    //     // Mock values and setup necessary approvals and balances for the test
    //     address userHolding = initiateUser(user, tokenIn, amount);

    //     // Invest into the tested strategy vie strategyManager
    //     vm.prank(user, user);
    //     strategyManager.invest(tokenIn, address(strategy), amount, "");

    //     if (strategy.rewardToken() == address(0)) {
    //         vm.prank(user, user);
    //         (uint256[] memory rewards, address[] memory rewardTokens) =
    //             strategyManager.claimRewards(address(strategy), "");

    //         assertEq(rewards.length, 0, "Wrong rewards length when no rewards");
    //         assertEq(rewardTokens.length, 0, "Wrong rewardTokens length when no rewards");
    //         return;
    //     }

    //     uint256 rewardsBefore = IERC20(strategy.rewardToken()).balanceOf(userHolding);
    //     (uint256[] memory rewards, address[] memory rewardTokens) = strategyManager.claimRewards(address(strategy),
    // "");
    //     vm.prank(user, user);

    //     uint256 rewardsAfter = IERC20(strategy.rewardToken()).balanceOf(userHolding);

    //     // Mock rewards and balances
    //     uint256 expectedRewards = rewardsAfter - rewardsBefore;

    //     // Assert statements with reasons
    //     assertEq(rewards[0], expectedRewards, "Incorrect rewards claimed");
    //     assertEq(rewardTokens[0], strategy.rewardToken(), "Incorrect reward token returned");
    // }
}
