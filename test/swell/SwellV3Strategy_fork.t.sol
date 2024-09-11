// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../fixtures/BasicContractsFixture.t.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ISwellVault} from "../../src/swell/SwellV3Strategy.sol";
import {SwellV3Strategy} from "../../src/swell/SwellV3Strategy.sol";
import {StakerLight} from "../../src/staker/StakerLight.sol";
import {StakerLightFactory} from "../../src/staker/StakerLightFactory.sol";

contract SwellV3StrategyTest is Test, BasicContractsFixture {
    event Deposit(
        address indexed asset,
        address indexed tokenIn,
        uint256 assetAmount,
        uint256 tokenInAmount,
        uint256 shares,
        address indexed recipient
    );

    SwellV3Strategy internal strategy;

    address internal swellVault = 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE;

    // Mainnet usdc
    address internal tokenIn = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    // Null token out
    address internal tokenOut = 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE;

    function setUp() public {
        init();

        address jRewards = address(new ERC20Mock());
        address stakerImplementation = address(new StakerLight());
        address stakerFactory = address(new StakerLightFactory({_initialOwner: OWNER}));

        address strategyImplementation = address(new SwellV3Strategy());

        SwellV3Strategy.InitializerParams memory initParams = SwellV3Strategy.InitializerParams({
            owner: OWNER,
            managerContainer: address(managerContainer),
            stakerFactory: address(stakerFactory),
            swellVault: swellVault,
            jigsawRewardToken: jRewards,
            jigsawRewardDuration: 60 days,
            tokenIn: tokenIn,
            tokenOut: tokenOut
        });

        bytes memory data = abi.encodeCall(SwellV3Strategy.initialize, initParams);

        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = SwellV3Strategy(proxy);

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
    function test_initialization() public {
        assertEq(strategy.owner(), OWNER, "Wrong owner");
        assertEq(address(strategy.managerContainer()), address(managerContainer), "Wrong managerContainer");
        assertEq(address(strategy.swellVault()), swellVault, "Wrong swellVault");
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
}