// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "../fixtures/BasicContractsFixture.t.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { IAToken } from "@aave/v3-core/interfaces/IAToken.sol";
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

        address strategyImplementation = address(new AaveV3Strategy());
        bytes memory data = abi.encodeCall(
            AaveV3Strategy.initialize,
            AaveV3Strategy.InitializerParams({
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
            })
        );

        address proxy = address(new ERC1967Proxy(strategyImplementation, data));
        strategy = AaveV3Strategy(proxy);

        // Add tested strategy to the StrategyManager for integration testing purposes
        vm.startPrank((OWNER));
        manager.whitelistToken(tokenIn);
        strategyManager.addStrategy(address(strategy));

        SharesRegistry tokenInSharesRegistry = new SharesRegistry(
            OWNER,
            address(managerContainer),
            address(tokenIn),
            address(usdcOracle),
            bytes(""),
            ISharesRegistry.RegistryConfig({
                collateralizationRate: 50_000,
                liquidationBuffer: 5e3,
                liquidatorBonus: 8e3
            })
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
    function test_deposit_when_wrongAsset(
        address asset
    ) public {
        vm.assume(asset != strategy.tokenIn());
        // Invest into the tested strategy vie strategyManager
        vm.prank(address(strategyManager), address(strategyManager));
        vm.expectRevert(bytes("3001"));
        strategy.deposit(asset, 1, address(1), "");
    }

    // Tests if deposit works correctly when authorized
    function test_aave_deposit_when_authorized(address user, uint256 _amount) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 10e6);
        address userHolding = initiateUser(user, tokenIn, amount);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        uint256 tokenOutBalanceBefore = IAToken(tokenOut).scaledBalanceOf(userHolding);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        (uint256 receiptTokens, uint256 tokenInAmount) = strategyManager.invest(tokenIn, address(strategy), amount, "");

        uint256 expectedShares = IAToken(tokenOut).scaledBalanceOf(userHolding) - tokenOutBalanceBefore;
        (uint256 investedAmount, uint256 totalShares) = strategy.recipients(userHolding);

        /**
         * Expected changes after deposit
         * 1. Holding tokenIn balance =  balance - amount
         * 2. Holding tokenOut balance += amount
         * 3. Staker receiptTokens balance += shares
         * 4. Strategy's invested amount  += amount
         * 5. Strategy's total shares  += shares
         */
        // 1.
        assertEq(IERC20(tokenIn).balanceOf(userHolding), tokenInBalanceBefore - amount, "Holding tokenIn balance wrong");
        // 2.
        assertApproxEqAbs(IERC20(tokenOut).balanceOf(userHolding), amount, 1, "Holding token out balance wrong");
        // 3.
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            expectedShares * 10 ** 12,
            "Incorrect receipt tokens minted"
        );
        //4.
        assertEq(investedAmount, amount, "Recipient invested amount mismatch");
        //5.
        assertEq(totalShares, expectedShares, "Recipient total shares mismatch");

        // Additional checks
        assertEq(receiptTokens, expectedShares, "Incorrect receipt tokens returned");
        assertEq(tokenInAmount, amount, "Incorrect tokenInAmount returned");
    }

    // Tests if withdraw reverts correctly when wrong asset
    function test_withdraw_when_wrongAsset(
        address asset
    ) public {
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
    function test_withdraw_aave_when_authorized(uint256 _amount, address user) public notOwnerNotZero(user) {
        uint256 amount = bound(_amount, 1e6, 10e6);
        address userHolding = initiateUser(user, tokenIn, amount);

        // Invest into the tested strategy vie strategyManager
        vm.prank(user, user);
        strategyManager.invest(tokenIn, address(strategy), amount, abi.encode("random ref"));

        (, uint256 totalShares) = strategy.recipients(userHolding);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(userHolding);
        (uint256 investedAmountBefore,) = strategy.recipients(userHolding);

        skip(100 days);

        uint256 fee =
            _getFeeAbsolute(IERC20(tokenOut).balanceOf(userHolding) - investedAmountBefore, manager.performanceFee());

        vm.prank(user, user);
        (uint256 assetAmount, uint256 tokenInAmount,,) = strategyManager.claimInvestment({
            _holding: userHolding,
            _token: tokenIn,
            _strategy: address(strategy),
            _shares: totalShares,
            _data: ""
        });

        (uint256 investedAmount, uint256 totalSharesAfter) = strategy.recipients(userHolding);
        uint256 tokenInBalanceAfter = IERC20(tokenIn).balanceOf(userHolding);
        uint256 expectedWithdrawal = tokenInBalanceAfter - tokenInBalanceBefore;

        /**
         * Expected changes after withdrawal
         * 1. Holding's tokenIn balance += (totalInvested + yield) * shareRatio
         * 2. Holding's tokenOut balance -= shares
         * 3. Staker receiptTokens balance -= shares
         * 4. Strategy's invested amount  -= totalInvested * shareRatio
         * 5. Strategy's total shares  -= shares
         * 6. Fee address fee amount += yield * performanceFee
         */
        // 1.
        assertEq(tokenInBalanceAfter, assetAmount, "Holding balance after withdraw is wrong");
        // 2.
        assertEq(IAToken(tokenOut).scaledBalanceOf(userHolding), 0, "Holding token out balance wrong");
        // 3.
        assertEq(
            IERC20(address(strategy.receiptToken())).balanceOf(userHolding),
            0,
            "Incorrect receipt tokens after withdraw"
        );
        // 4.
        assertEq(investedAmount, 0, "Recipient invested amount mismatch");
        // 5.
        assertEq(totalSharesAfter, 0, "Recipient total shares mismatch after withdrawal");
        // 6.
        assertEq(fee, IERC20(tokenIn).balanceOf(manager.feeAddress()), "Fee address fee amount wrong");

        // Additional checks
        assertEq(assetAmount, expectedWithdrawal, "Incorrect asset amount returned");
        assertEq(tokenInAmount, investedAmountBefore, "Incorrect tokenInAmount returned");
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
