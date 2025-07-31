// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BytesLib } from "@uniswap/v3-periphery/contracts/libraries/BytesLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { GenericUniswapV3Oracle } from "@jigsaw/src/oracles/uniswap/GenericUniswapV3Oracle.sol";

import { ISwapRouter } from "@jigsaw/lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IHolding } from "@jigsaw/src/interfaces/core/IHolding.sol";
import { IHoldingManager } from "@jigsaw/src/interfaces/core/IHoldingManager.sol";
import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IStablesManager } from "@jigsaw/src/interfaces/core/IStablesManager.sol";

import { IReceiptToken } from "@jigsaw/src/interfaces/core/IReceiptToken.sol";
import { IStrategy } from "@jigsaw/src/interfaces/core/IStrategy.sol";
import { ISwapManager } from "@jigsaw/src/interfaces/core/ISwapManager.sol";
import { IOracle } from "@jigsaw/src/interfaces/oracle/IOracle.sol";

import { IStakerLight } from "../staker/interfaces/IStakerLight.sol";
import { IStakerLightFactory } from "../staker/interfaces/IStakerLightFactory.sol";
import { IERC4626, ISdeUsdMin } from "./interfaces/ISdeUsdMin.sol";

import { StrategyBaseUpgradeableV2 } from "../StrategyBaseUpgradeableV2.sol";

import { IFeeManager } from "../extensions/interfaces/IFeeManager.sol";
import { OperationsLib } from "../libraries/OperationsLib.sol";
import { StrategyConfigLib } from "../libraries/StrategyConfigLib.sol";
import { OracleLib } from "./libraries/OracleLib.sol";

/**
 * @title ElixirStrategy
 * @dev Strategy used for deUSD minting and staking mechanisms.
 * @notice Implements deposit, withdrawal, and reward management for Elixir's deUSD strategy.
 * @author Hovooo (@hovooo)
 */
contract ElixirStrategy is IStrategy, StrategyBaseUpgradeableV2 {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;
    using BytesLib for bytes;

    // -- Enums --

    /**
     * @notice The direction of the swap.
     */
    enum SwapDirection {
        FromTokenIn,
        ToTokenIn
    }

    // -- Custom types --

    /**
     * @notice Struct for the initializer params.
     */
    struct InitializerParams {
        address owner; // The address of the initial owner of the Strategy contract
        address manager; // The address of the manager contract
        address stakerFactory; // The address of the StakerLightFactory contract
        address jigsawRewardToken; // The address of the Jigsaw reward token associated with the strategy
        uint256 jigsawRewardDuration; // The address of the initial Jigsaw reward distribution duration for the strategy
        address tokenIn; // The address of the LP token
        address tokenOut; // The address of Elixir's receipt token
        address deUSD; // The Elixir's deUSD stablecoin.
        address uniswapRouter; // The address of the UniswapV3 Router
        address oracle; // The address of the UniswapV3 Oracle
        address[] initialPools; // The address array of the UniswapV3 pools
        address feeManager; // The address of the feeManager contract
        SwapDirection[] swapDirections; // Array specifying the swap directions swap paths are set during initialization
        bytes[] swapPaths; // Array of encoded UniswapV3 swap paths corresponding to each swap direction
    }

    // -- Errors --

    /**
     * @notice Thrown when an unsupported operation is attempted.
     */
    error OperationNotSupported();

    /**
     * @notice Thrown when the swap path length is invalid.
     */
    error InvalidSwapPathLength();

    /**
     * @notice Thrown when the first token in the swap path is invalid.
     */
    error InvalidFirstTokenInPath();

    /**
     * @notice Thrown when the last token in the swap path is invalid.
     */
    error InvalidLastTokenInPath();

    /**
     *  @notice Thrown when the minimum output amount is invalid.
     *  @param provided The minimum output amount provided by the user.
     *  @param allowed The minimum output amount allowed by the strategy (after slippage).
     */
    error InvalidAmountOutMin(uint256 provided, uint256 allowed);

    // -- Events --

    /**
     * @notice Emitted when the slippage percentage is updated.
     * @param oldValue The previous slippage percentage value.
     * @param newValue The new slippage percentage value.
     */
    event SlippagePercentageSet(uint256 oldValue, uint256 newValue);

    /**
     * @notice Emitted when exact input swap is executed on UniswapV3 Pool.
     * @param holding The holding address associated with the user.
     * @param path The optimal path for the multi-hop swap.
     * @param amountIn The amount of the input token used for the swap.
     * @param amountOut The amount of the output token received after the swap.
     */
    event ExactInputSwap(address indexed holding, bytes path, uint256 amountIn, uint256 amountOut);

    /**
     * @notice Emitted when the oracle is updated.
     * @param oldOracle The old oracle address.
     * @param newOracle The new oracle address.
     */
    event OracleUpdated(address oldOracle, address newOracle);

    /**
     * @notice Emitted when the swap path is updated for a given swap direction.
     * @param swapDirection The direction of the swap (FromTokenIn or ToTokenIn).
     * @param swapPath The encoded swap path as bytes.
     */
    event SwapPathUpdated(SwapDirection indexed swapDirection, bytes indexed swapPath);

    // -- State variables --

    /**
     * @notice The tokenIn address for the strategy.
     */
    address public override tokenIn;

    /**
     * @notice The tokenOut address (deUSD) for the strategy.
     */
    address public override tokenOut;

    /**
     * @notice The reward token offered to users.
     */
    address public override rewardToken;

    /**
     * @notice The receipt token associated with this strategy.
     */
    IReceiptToken public override receiptToken;

    /**
     * @notice The Elixir's Stablecoin deUSD.
     */
    address public deUSD;

    /**
     * @notice The Uniswap Router.
     */
    address public uniswapRouter;

    /**
     * @notice The Jigsaw Rewards Controller contract.
     */
    IStakerLight public jigsawStaker;

    /**
     * @notice The sdeUSD Controller contract.
     */
    ISdeUsdMin public sdeUSD;

    /**
     * @notice The oracle contract used to calculate and validate minimum output amounts for UniswapV3 swaps.
     */
    IOracle public oracle;

    /**
     * @notice The number of decimals of the strategy's shares.
     */
    uint256 public override sharesDecimals;

    /**
     * @notice Returns the maximum allowed slippage percentage.
     * @dev Uses 2 decimal precision, where 1% is represented as 100.
     */
    uint256 public allowedSlippagePercentage;

    /**
     * @notice The slippage factor.
     */
    uint256 public constant SLIPPAGE_PRECISION = 1e4;

    /**
     * @notice The length of the bytes encoded address.
     */
    uint256 private constant ADDR_SIZE = 20;

    /**
     * @notice A mapping that stores participant details by address.
     */
    mapping(address recipient => IStrategy.RecipientInfo info) public override recipients;

    /**
     * @notice Mapping of recipient addresses to the number of shares pending withdrawal after initiating cooldown.
     * @dev Used to track shares that are in the cooldown period before they can be withdrawn.
     */
    mapping(address recipient => uint256 sharesInCooldown) public sharesPendingCooldown;

    /**
     * @notice Stores the UniswapV3 swap path for each swap direction.
     * @dev The mapping associates a SwapDirection with its corresponding encoded swap path.
     * The swap path is used to perform token swaps via UniswapV3 for the specified direction.
     */
    mapping(SwapDirection direction => bytes SwapPath) public swapPath;

    /**
     * @notice The factor used to adjust values from 18 decimal precision (shares) to 6 decimal precision (USDC).
     */
    uint256 public constant DECIMAL_DIFF = 1e12;

    // -- Constructor --

    /**
     * @notice Disables initializers to prevent misuse.
     */
    constructor() {
        _disableInitializers();
    }

    // -- Initialization --

    /**
     * @notice Initializes the Elixir Strategy contract with necessary parameters.
     *
     * @dev Configures core components such as manager, tokens, pools, and reward systems needed for the strategy to
     * operate.
     *
     * @dev This function is only callable once due to the `initializer` modifier.
     *
     * @notice Ensures that critical addresses are non-zero to prevent misconfiguration:
     * - `_params.manager` must be valid (`"3065"` error code if invalid).
     * - `_params.tokenIn` and `_params.tokenOut` must be valid (`"3000"` error code if invalid).
     * - `_params.feeManager` must be valid (`"3000"` error code if invalid).
     *
     * @param _params Struct containing all initialization parameters.
     */
    function initialize(
        InitializerParams memory _params
    ) public initializer {
        require(_params.manager != address(0), "3065");
        require(_params.jigsawRewardToken != address(0), "3000");
        require(_params.tokenIn != address(0), "3000");
        require(_params.tokenOut != address(0), "3000");
        require(_params.deUSD != address(0), "3036");
        require(_params.feeManager != address(0), "3000");

        __StrategyBase_init({ _initialOwner: _params.owner });

        manager = IManager(_params.manager);
        tokenIn = _params.tokenIn;
        tokenOut = _params.tokenOut;
        sharesDecimals = IERC20Metadata(_params.tokenOut).decimals();
        rewardToken = address(0);
        deUSD = _params.deUSD;
        sdeUSD = ISdeUsdMin(_params.tokenOut);
        feeManager = IFeeManager(_params.feeManager);

        receiptToken = IReceiptToken(
            StrategyConfigLib.configStrategy({
                _initialOwner: _params.owner,
                _receiptTokenFactory: manager.receiptTokenFactory(),
                _receiptTokenName: "Elixir Receipt Token",
                _receiptTokenSymbol: "ElRT"
            })
        );

        jigsawStaker = IStakerLight(
            IStakerLightFactory(_params.stakerFactory).createStakerLight({
                _initialOwner: _params.owner,
                _holdingManager: manager.holdingManager(),
                _rewardToken: _params.jigsawRewardToken,
                _strategy: address(this),
                _rewardsDuration: _params.jigsawRewardDuration
            })
        );

        if (tokenIn != deUSD) {
            require(_params.oracle != address(0), "3000");
            require(_params.uniswapRouter != address(0), "3000");
            require(_params.initialPools.length != 0, "3000");
            require(_params.swapDirections.length != 0, "3000");
            require(_params.swapPaths.length != 0, "3000");

            oracle = OracleLib.deployUniswapOracle({
                _initialOwner: _params.owner,
                _underlying: _params.deUSD,
                _quoteToken: _params.tokenIn,
                _quoteTokenOracle: _params.oracle,
                _uniswapV3Pools: _params.initialPools
            });

            uniswapRouter = _params.uniswapRouter;

            // Set default allowed slippage percentage to 5%
            _setSlippagePercentage({ _newVal: 500 });
            _setSwapPath({ _swapDirections: _params.swapDirections, _swapPaths: _params.swapPaths });
        }
    }

    // -- User-specific Methods --

    /**
     * @notice Deposits funds into the strategy.
     *
     * @param _asset The token to be invested.
     * @param _amount The amount of the token to be invested.
     * @param _recipient The address on behalf of which the funds are deposited.
     * @param _data Encoded data used for UniswapV3 swap.
     *
     * @return The amount of receipt tokens obtained.
     * @return The amount of the 'tokenIn()' token.
     */
    function deposit(
        address _asset,
        uint256 _amount,
        address _recipient,
        bytes calldata _data
    ) external override nonReentrant onlyValidAmount(_amount) onlyStrategyManager returns (uint256, uint256) {
        require(_asset == tokenIn, "3001");

        uint256 deUsdBalanceBefore = IERC20(deUSD).balanceOf(address(this));
        IHolding(_recipient).transfer({ _token: _asset, _to: address(this), _amount: _amount });

        if (tokenIn != deUSD) {
            // Swap USDT to deUSD on Uniswap
            _swapExactInputMultihop({
                _tokenIn: _asset,
                _amountIn: _amount,
                _recipient: address(this),
                _swapData: _data,
                _swapDirection: SwapDirection.FromTokenIn
            });
        }

        uint256 deUSDAmount = IERC20(deUSD).balanceOf(address(this)) - deUsdBalanceBefore;
        uint256 balanceBefore = sdeUSD.balanceOf(_recipient);
        IERC20(deUSD).forceApprove({ spender: tokenOut, value: deUSDAmount });

        // Stake deUSD to receive sdeUSD (Elixir's staked deUSD receipt token)
        sdeUSD.deposit({ assets: deUSDAmount, receiver: _recipient });

        uint256 shares = sdeUSD.balanceOf(_recipient) - balanceBefore;

        recipients[_recipient].investedAmount += _amount;
        recipients[_recipient].totalShares += shares;

        _mint({ _receiptToken: receiptToken, _recipient: _recipient, _amount: shares, _tokenDecimals: sharesDecimals });

        jigsawStaker.deposit({ _user: _recipient, _amount: shares });

        emit Deposit({
            asset: _asset,
            tokenIn: tokenIn,
            assetAmount: _amount,
            tokenInAmount: _amount,
            shares: shares,
            recipient: _recipient
        });

        return (shares, _amount);
    }

    /**
     * @notice Withdraws deposited funds from the strategy.
     *
     * @dev Some strategies will only allow the tokenIn to be withdrawn.
     * @dev 'assetAmount' will be equal to 'tokenInAmount' if '_asset' is the same as the strategy's 'tokenIn()'.
     *
     * @dev Frontend: Before allowing a withdrawal, ensure that if the cooldown mechanism is active in the sdeUSD
     * contract, the user has already initiated the cooldown process. This can be checked by calling the
     * `isCooldownActive` function of the strategy. If cooldown is active, also verify that the user has shares
     * registered for withdrawal in the `sharesPendingCooldown` mapping.
     * If these conditions are not met, prevent the withdrawal and prompt the user to initiate cooldown first.
     *
     * @param _shares The amount of shares to withdraw.
     * @param _recipient The address on behalf of which the funds are withdrawn.
     * @param _asset The token to be withdrawn.
     * @param _data The data containing the token output .
     *
     * @return withdrawnAmount The actual amount of asset withdrawn from the strategy.
     * @return initialInvestment The amount of initial investment.
     * @return yield The amount of yield generated by the user beyond their initial investment.
     * @return fee The amount of fee charged by the strategy.
     */
    function withdraw(
        uint256 _shares,
        address _recipient,
        address _asset,
        bytes calldata _data
    ) external override nonReentrant onlyStrategyManager returns (uint256, uint256, int256, uint256) {
        require(_asset == tokenIn, "3001");

        bool cooldownActive = isCooldownActive();
        WithdrawParams memory params = WithdrawParams({
            shares: cooldownActive ? sharesPendingCooldown[_recipient] : _shares,
            totalShares: recipients[_recipient].totalShares,
            shareRatio: 0,
            shareDecimals: sharesDecimals,
            investment: 0,
            assetsToWithdraw: 0,
            balanceBefore: IERC20(tokenIn).balanceOf(_recipient),
            withdrawnAmount: 0,
            yield: 0,
            fee: 0
        });

        if (cooldownActive) require(params.shares > 0, "No shares to redeem. Cooldown first");

        params.shareRatio = OperationsLib.getRatio({
            numerator: params.shares,
            denominator: params.totalShares,
            precision: params.shareDecimals,
            rounding: OperationsLib.Rounding.Floor
        });

        _burn({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _shares: params.shares,
            _totalShares: params.totalShares,
            _tokenDecimals: params.shareDecimals
        });

        params.investment = (recipients[_recipient].investedAmount * params.shareRatio) / 10 ** params.shareDecimals;
        uint256 deUsdBalanceBefore = IERC20(deUSD).balanceOf(address(this));

        _genericCall({
            _holding: _recipient,
            _contract: tokenOut,
            _call: cooldownActive
                ? abi.encodeCall(ISdeUsdMin.unstake, (address(this)))
                : abi.encodeCall(IERC4626.redeem, (params.shares, address(this), _recipient))
        });

        uint256 deUsdAmount = IERC20(deUSD).balanceOf(address(this)) - deUsdBalanceBefore;

        if (tokenIn == deUSD) {
            IERC20(deUSD).safeTransfer({ to: _recipient, value: deUsdAmount });
        }

        // Swap deUSD to USDT on Uniswap if the tokenIn of the strategy is not deUSD
        params.withdrawnAmount = tokenIn == deUSD
            ? deUsdAmount
            : _swapExactInputMultihop({
                _tokenIn: deUSD,
                _amountIn: deUsdAmount,
                _recipient: _recipient,
                _swapData: _data,
                _swapDirection: SwapDirection.ToTokenIn
            });

        // Take protocol's fee from generated yield if any.
        params.yield = params.withdrawnAmount.toInt256() - params.investment.toInt256();

        // Take protocol's fee from generated yield if any.
        if (params.yield > 0) {
            params.fee = _takePerformanceFee({ _token: tokenIn, _recipient: _recipient, _yield: uint256(params.yield) });
            if (params.fee > 0) {
                params.withdrawnAmount -= params.fee;
                params.yield -= params.fee.toInt256();
            }
        }

        sharesPendingCooldown[_recipient] = 0;
        recipients[_recipient].totalShares -= params.shares;
        recipients[_recipient].investedAmount = params.investment > recipients[_recipient].investedAmount
            ? 0
            : recipients[_recipient].investedAmount - params.investment;

        emit Withdraw({
            asset: _asset,
            recipient: _recipient,
            shares: params.shares,
            withdrawnAmount: params.withdrawnAmount,
            initialInvestment: params.investment,
            yield: params.yield
        });

        // Register `_recipient`'s withdrawal operation to stop generating jigsaw rewards.
        jigsawStaker.withdraw({ _user: _recipient, _amount: params.shares });

        return (params.withdrawnAmount, params.investment, params.yield, params.fee);
    }

    /**
     * @notice Claims rewards from Elixir.
     * @return The amounts of rewards claimed.
     * @return The addresses of the reward tokens.
     */
    function claimRewards(
        address,
        bytes calldata
    ) external pure override returns (uint256[] memory, address[] memory) {
        revert OperationNotSupported();
    }

    /**
     * @notice Forces the unstaking of shares for a given recipient
     *
     * @dev Call this function to force-unstake shares that have completed their cooldown period but were not withdrawn
     * while `isCooldownActive` was true. This allows recovery of shares that are pending withdrawal after cooldown
     * expiration.
     * @dev Can only be called by the contract owner or the holding user associated with the recipient.
     *
     * @param _recipient The address of the recipient whose shares are to be force-unstaked.
     * @param _data Additional data required for the swap operation.
     */
    function forceUnstake(address _recipient, bytes calldata _data) external nonReentrant {
        require(
            msg.sender == owner() || msg.sender == IHoldingManager(manager.holdingManager()).holdingUser(_recipient),
            "1001"
        );

        uint256 totalShares = recipients[_recipient].totalShares;
        uint256 sharesToUnstake = sharesPendingCooldown[_recipient];

        require(sharesToUnstake != 0, "Nothing to force unstake");

        uint256 shareRatio = OperationsLib.getRatio({
            numerator: sharesToUnstake,
            denominator: totalShares,
            precision: sharesDecimals,
            rounding: OperationsLib.Rounding.Floor
        });

        _burn({
            _receiptToken: receiptToken,
            _recipient: _recipient,
            _shares: sharesToUnstake,
            _totalShares: totalShares,
            _tokenDecimals: sharesDecimals
        });

        uint256 investment = (recipients[_recipient].investedAmount * shareRatio) / 10 ** sharesDecimals;
        uint256 deUsdBalanceBefore = IERC20(deUSD).balanceOf(address(this));

        _genericCall({
            _holding: _recipient,
            _contract: tokenOut,
            _call: abi.encodeCall(ISdeUsdMin.unstake, (address(this)))
        });

        uint256 deUsdAmount = IERC20(deUSD).balanceOf(address(this)) - deUsdBalanceBefore;

        if (tokenIn == deUSD) {
            IERC20(deUSD).safeTransfer({ to: _recipient, value: deUsdAmount });
        }

        // Swap deUSD to USDT on Uniswap if the tokenIn of the strategy is not deUSD
        uint256 withdrawnAmount = tokenIn == deUSD
            ? deUsdAmount
            : _swapExactInputMultihop({
                _tokenIn: deUSD,
                _amountIn: deUsdAmount,
                _recipient: _recipient,
                _swapData: _data,
                _swapDirection: SwapDirection.ToTokenIn
            });

        // Take protocol's fee from generated yield if any.
        int256 yield = withdrawnAmount.toInt256() - investment.toInt256();

        // Take protocol's fee from generated yield if any.
        if (yield > 0) {
            uint256 fee = _takePerformanceFee({ _token: tokenIn, _recipient: _recipient, _yield: uint256(yield) });
            if (fee > 0) {
                withdrawnAmount -= fee;
                yield -= fee.toInt256();
            }
        }

        sharesPendingCooldown[_recipient] = 0;
        recipients[_recipient].totalShares -= sharesToUnstake;
        recipients[_recipient].investedAmount =
            investment > recipients[_recipient].investedAmount ? 0 : recipients[_recipient].investedAmount - investment;

        emit Withdraw({
            asset: tokenIn,
            recipient: _recipient,
            shares: sharesToUnstake,
            withdrawnAmount: withdrawnAmount,
            initialInvestment: investment,
            yield: yield
        });

        // Register `_recipient`'s withdrawal operation to stop generating jigsaw rewards.
        jigsawStaker.withdraw({ _user: _recipient, _amount: sharesToUnstake });
    }

    /**
     * @notice Initiates the cooldown period required before a user can withdraw the converted underlying asset.
     * @dev Only the contract owner or the user associated with the holding can call this function.
     * @param _recipient The address on behalf of which the funds are withdrawn.
     * @param _shares The amount of shares to withdraw (must not exceed available shares).
     */
    function cooldown(address _recipient, uint256 _shares) external nonReentrant {
        require(isCooldownActive(), "Cooldown is inactive. Withdraw directly");
        require(
            msg.sender == owner() || msg.sender == IHoldingManager(manager.holdingManager()).holdingUser(_recipient),
            "1001"
        );
        if (msg.sender != owner()) {
            require(
                !IStablesManager(manager.stablesManager()).isLiquidatable({ _token: tokenIn, _holding: _recipient }),
                "3105"
            );
        }

        // Prevent overflow and excessive withdrawal
        uint256 newPending = sharesPendingCooldown[_recipient] + _shares;
        require(newPending <= recipients[_recipient].totalShares, "Excessive shares amount");
        sharesPendingCooldown[_recipient] = newPending;

        // Call cooldownShares on the sdeUSD contract for the specified amount
        _genericCall({
            _holding: _recipient,
            _contract: tokenOut,
            _call: abi.encodeCall(ISdeUsdMin.cooldownShares, _shares)
        });
    }

    // -- Administration --

    /**
     * @notice Sets a new slippage percentage for the strategy.
     * @param _newVal The new slippage percentage value (must be <= SLIPPAGE_PRECISION).
     */
    function setSlippagePercentage(
        uint256 _newVal
    ) external onlyOwner {
        _setSlippagePercentage({ _newVal: _newVal });
    }

    /**
     * @notice Updates the oracle contract.
     *
     * @dev The oracle is used to calculate and validate minimum output amounts for UniswapV3 swaps.
     * @dev Ensure the new oracle is compatible with the `getAllowedAmountOutMin()`'s requirements.
     *
     * @param _newOracle The new oracle address.
     */
    function updateOracle(
        address _newOracle
    ) external onlyOwner {
        require(_newOracle != address(0), "3000");
        require(_newOracle != address(oracle), "3017");

        emit OracleUpdated({ oldOracle: address(oracle), newOracle: _newOracle });
        oracle = IOracle(_newOracle);
    }

    function setSwapPath(SwapDirection[] memory _swapDirections, bytes[] memory _swapPaths) external onlyOwner {
        _setSwapPath(_swapDirections, _swapPaths);
    }

    // -- Getters --

    /**
     * @notice Returns the address of the receipt token.
     */
    function getReceiptTokenAddress() external view override returns (address) {
        return address(receiptToken);
    }

    /**
     * @notice Calculates the minimum acceptable amount
     * @param _amount The amount of shares.
     * @return The minimum acceptable asset tokens received for specified shares amount.
     */
    function getAllowedAmountOutMin(uint256 _amount, SwapDirection _swapDirection) public view returns (uint256) {
        // Get tokenIn rate to get  minimum acceptable amount out
        (, uint256 rate) = oracle.peek(bytes(""));

        // Account for decimal difference
        uint256 expectedTokenOut = (_swapDirection == SwapDirection.FromTokenIn)
            // USDT → deUSD: Scale up by 12 decimals (18 - 6)
            ? _amount.mulDiv(rate, 1e18, Math.Rounding.Ceil) * DECIMAL_DIFF
            // deUSD → USDT: Scale down by 12 decimals (18 - 6)
            : _amount.mulDiv(1e18, rate, Math.Rounding.Ceil) / DECIMAL_DIFF;

        // Calculate min tokenOut amount with max allowed slippage
        return _applySlippage(expectedTokenOut);
    }

    /**
     * @notice Checks if the cooldown period is currently active for sdeUSD withdrawals.
     * @dev Returns true if the cooldown duration set in the sdeUSD contract is greater than zero.
     * @return True if cooldown is active, false otherwise.
     */
    function isCooldownActive() public view returns (bool) {
        return sdeUSD.cooldownDuration() > 0;
    }

    // -- Utilities --

    /**
     * @notice Swaps a fixed amount of `_tokenIn` for a maximum possible amount of `tokenOut` via `_swapPath`.
     *
     * @notice Effects:
     * - Approves and transfers `tokenIn` from the `_userHolding`.
     * - Approves UniswapV3 Router to transfer `tokenIn` from address(this) to perform the `exactInput` swap.
     * - Executes the `exactInput` swap
     * - Handles any excess tokens.
     *
     * @param _tokenIn The address of the inbound asset.
     * @param _amountIn The desired amount of `tokenIn`.
     * @param _recipient The address of recipient.
     * @param _swapData Encoded data used for UniswapV3 swap.
     * @param _swapDirection The direction of the swap.
     *
     * @return amountOut The amount of `_tokenIn` spent to receive the desired `amountOut` of `tokenOut`.
     */
    function _swapExactInputMultihop(
        address _tokenIn,
        uint256 _amountIn,
        address _recipient,
        bytes calldata _swapData,
        SwapDirection _swapDirection
    ) private returns (uint256 amountOut) {
        // Decode the data to get the swap path
        (uint256 amountOutMinimum, uint256 deadline) = abi.decode(_swapData, (uint256, uint256));
        uint256 allowedAmountOutMin = getAllowedAmountOutMin(_amountIn, _swapDirection);

        // Validate amountOutMin is within allowed slippage
        if (amountOutMinimum < allowedAmountOutMin) {
            revert InvalidAmountOutMin({ provided: amountOutMinimum, allowed: allowedAmountOutMin });
        }

        // Approve the router to spend `_tokenIn`.
        IERC20(_tokenIn).forceApprove({ spender: uniswapRouter, value: _amountIn });

        // A path is a  encoded as (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut).
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: swapPath[_swapDirection],
            recipient: _recipient,
            deadline: deadline,
            amountIn: _amountIn,
            amountOutMinimum: amountOutMinimum
        });

        // Execute the swap, returning the amountIn actually spent.
        try ISwapRouter(uniswapRouter).exactInput(params) returns (uint256 _amountOut) {
            amountOut = _amountOut;
        } catch {
            revert("3084");
        }

        // Emit event indicating successful exact output swap.
        emit ExactInputSwap({
            holding: _recipient,
            path: swapPath[_swapDirection],
            amountIn: _amountIn,
            amountOut: amountOut
        });
    }

    /**
     * @notice Applies slippage tolerance to a given value.
     * @dev Reduces the input value by the configured slippage percentage.
     * @param _value The value to apply slippage to.
     * @return The value after slippage has been applied (reduced).
     */
    function _applySlippage(
        uint256 _value
    ) private view returns (uint256) {
        return _value - ((_value * allowedSlippagePercentage) / SLIPPAGE_PRECISION);
    }

    /**
     * @notice Sets a new slippage percentage for the strategy.
     * @dev Emits a SlippagePercentageSet event.
     * @param _newVal The new slippage percentage value (must be <= SLIPPAGE_PRECISION).
     */
    function _setSlippagePercentage(
        uint256 _newVal
    ) private {
        require(_newVal <= SLIPPAGE_PRECISION, "3002");
        emit SlippagePercentageSet({ oldValue: allowedSlippagePercentage, newValue: _newVal });
        allowedSlippagePercentage = _newVal;
    }

    /**
     * @notice Sets the swap paths for the specified swap directions.
     *
     * @dev This function allows setting multiple swap paths for different swap directions in a single call.
     *      It validates the swap path length and ensures the correct token order for each direction:
     *      - For SwapDirection.FromTokenIn: path must start with `tokenIn` and end with `deUSD`.
     *      - For SwapDirection.ToTokenIn: path must start with `deUSD` and end with `tokenIn`.
     *      Emits a {SwapPathUpdated} event for each successfully set path.
     *
     * @param _swapDirections The array of swap directions (FromTokenIn or ToTokenIn).
     * @param _swapPaths The array of encoded swap paths as bytes, corresponding to each direction.
     */
    function _setSwapPath(SwapDirection[] memory _swapDirections, bytes[] memory _swapPaths) private {
        require(_swapDirections.length == _swapPaths.length, "3047");

        for (uint256 i = 0; i < _swapDirections.length; i++) {
            bytes memory path = _swapPaths[i];

            // Minimum path length is 43 bytes (address[20] + fee[3] + address[20])
            if (path.length < 43) revert InvalidSwapPathLength();

            if (_swapDirections[i] == SwapDirection.FromTokenIn) {
                // Path must start with tokenIn and end with deUSD
                if (path.toAddress(0) != tokenIn) revert InvalidFirstTokenInPath();
                if (path.toAddress(path.length - ADDR_SIZE) != deUSD) revert InvalidLastTokenInPath();
            } else if (_swapDirections[i] == SwapDirection.ToTokenIn) {
                // Path must start with deUSD and end with tokenIn
                if (path.toAddress(0) != deUSD) revert InvalidFirstTokenInPath();
                if (path.toAddress(path.length - ADDR_SIZE) != tokenIn) revert InvalidLastTokenInPath();
            } else {
                revert("Invalid SwapDirection");
            }

            swapPath[_swapDirections[i]] = path;
            emit SwapPathUpdated({ swapDirection: _swapDirections[i], swapPath: path });
        }
    }
}
