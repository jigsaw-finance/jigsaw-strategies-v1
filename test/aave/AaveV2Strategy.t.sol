// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../fixtures/BasicContractsFixture.t.sol";

import { AaveV2Strategy } from "../../src/aave/AaveV2Strategy.sol";

import { IAaveV2IncentivesController } from "../../src/aave/interfaces/IAaveV2IncentivesController.sol";
import { IAaveV2LendingPool } from "../../src/aave/interfaces/IAaveV2LendingPool.sol";

contract AaveV2StrategyTest is Test, BasicContractsFixture {
    event Deposit(
        address indexed asset,
        address indexed tokenIn,
        uint256 assetAmount,
        uint256 tokenInAmount,
        uint256 shares,
        address indexed recipient
    );

    AaveV2Strategy internal strategy;

    // One aave lending pool for all
    address internal lendingPool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address internal incentivesController = 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5;

    // Mainnet usdc
    address internal tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Aave interest bearing aUSDC
    address internal tokenOut = 0xBcca60bB61934080951369a648Fb03DF4F96263C;

    string internal receiptTokenName = "Receipt Token";
    string internal receiptTokenSymbol = "RTK";

    function setUp() public {
        init();

        strategy = new AaveV2Strategy({
            _owner: OWNER,
            _managerContainer: address(managerContainer),
            _lendingPool: lendingPool,
            _incentivesController: incentivesController,
            _tokenIn: tokenIn,
            _tokenOut: tokenOut,
            _receiptTokenName: receiptTokenName,
            _receiptTokenSymbol: receiptTokenSymbol
        });

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

    // Example of a test for the constructor
    function test_constructor_when_parametersAreValid() public view {
        assertEq(address(strategy.managerContainer()), address(managerContainer), "Manager container address mismatch");
        assertEq(address(strategy.lendingPool()), lendingPool, "Lending pool address mismatch");
        assertEq(
            address(strategy.incentivesController()), incentivesController, "Incentives controller address mismatch"
        );
        assertEq(strategy.tokenIn(), tokenIn, "TokenIn address mismatch");
        assertEq(strategy.tokenOut(), tokenOut, "TokenOut address mismatch");
        assertEq(strategy.rewardToken(), strategy.incentivesController().REWARD_TOKEN(), "Reward token mismatch");
        assertEq(strategy.sharesDecimals(), IERC20Metadata(tokenOut).decimals(), "Shares decimals mismatch");
    }

    // Test when one of the constructor parameters is invalid
    function test_constructor_when_managerContainerIsZero() public {
        vm.expectRevert(bytes("3065"));
        new AaveV2Strategy(
            OWNER,
            address(0),
            lendingPool,
            incentivesController,
            tokenIn,
            tokenOut,
            receiptTokenName,
            receiptTokenSymbol
        );
    }

    // Test when the lending pool address is zero
    function test_constructor_when_lendingPoolIsZero() public {
        vm.expectRevert(bytes("3036"));
        new AaveV2Strategy(
            OWNER,
            address(managerContainer),
            address(0),
            incentivesController,
            tokenIn,
            tokenOut,
            receiptTokenName,
            receiptTokenSymbol
        );
    }

    // Test when the incentives controller address is zero
    function test_constructor_when_incentivesControllerIsZero() public {
        vm.expectRevert(bytes("3039"));
        new AaveV2Strategy(
            OWNER,
            address(managerContainer),
            lendingPool,
            address(0),
            tokenIn,
            tokenOut,
            receiptTokenName,
            receiptTokenSymbol
        );
    }

    // Test when the tokenIn address is zero
    function test_constructor_when_tokenInIsZero() public {
        vm.expectRevert(bytes("3000"));
        new AaveV2Strategy(
            OWNER,
            address(managerContainer),
            lendingPool,
            incentivesController,
            address(0),
            tokenOut,
            receiptTokenName,
            receiptTokenSymbol
        );
    }

    // Test when the tokenOut address is zero
    function test_constructor_when_tokenOutIsZero() public {
        vm.expectRevert(bytes("3000"));
        new AaveV2Strategy(
            OWNER,
            address(managerContainer),
            lendingPool,
            incentivesController,
            tokenIn,
            address(0),
            receiptTokenName,
            receiptTokenSymbol
        );
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
    function test_claimRewards_when_authorized() public {
        address user = vm.addr(uint256(keccak256(bytes("Random user address"))));
        uint256 amount = 100e6;

        // Mock values and setup necessary approvals and balances for the test
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, "");

        // Fast forward 100 days to generate rewards
        vm.warp(100 days);

        uint256 rewardsBefore = IERC20(strategy.rewardToken()).balanceOf(userHolding);

        vm.prank(user, user);
        (uint256[] memory rewards, address[] memory rewardTokens) = strategyManager.claimRewards(address(strategy), "");

        uint256 rewardsAfter = IERC20(strategy.rewardToken()).balanceOf(userHolding);

        // Mock rewards and balances
        uint256 expectedRewards = rewardsAfter - rewardsBefore;

        // Assert statements with reasons
        assertEq(rewards[0], expectedRewards, "Incorrect rewards claimed");
        assertEq(rewardTokens[0], strategy.rewardToken(), "Incorrect reward token returned");
    }
}
