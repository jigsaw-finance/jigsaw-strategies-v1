// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IManager } from "@jigsaw/src/interfaces/core/IManager.sol";
import { IStrategyManager } from "@jigsaw/src/interfaces/core/IStrategyManager.sol";

/**
 * @title FeeManager Contract used for custom fee functionality through Jigsaw Strategies.
 * @author Hovooo (@hovooo)
 */
contract FeeManager is Ownable2Step, ReentrancyGuard {
    /**
     * @notice Emitted when the default fee is updated.
     * @param strategy The strategy address.
     * @param holding The holding address.
     * @param oldFee The previous fee.
     * @param newFee The new fee.
     */
    event HoldingCustomFeeUpdated(address strategy, address holding, uint256 indexed oldFee, uint256 indexed newFee);

    /**
     * @notice Contract that contains the address of the manager contract.
     */
    IManager public manager;

    /**
     * @notice Returns holdingCustomFee associated with the strategy and holding.
     */
    mapping(address strategy => mapping(address holding => uint256 customFee)) public holdingCustomFee;

    /**
     * @notice Creates a new FeeManager contract.
     * @param _initialOwner The address of the initial owner of the contract.
     * @param _manager The address of the Manager contract.
     */
    constructor(
        address _initialOwner,
        address _manager
    ) Ownable(_initialOwner) {
        manager = IManager(_manager);
    }

    /**
     * @notice Sets a custom fee for a list of holding.
     * @param _strategies The address list of the strategies.
     * @param _holdings The address list of the holdings.
     * @param _vals The custom fee list to set.
     */
    function setHoldingCustomFees(address[] calldata _strategies, address[] calldata _holdings, uint256[] calldata _vals) external {
        require(_strategies.length == _holdings.length, "3047");
        require(_strategies.length == _vals.length, "3047");

        for (uint256 i = 0; i < _strategies.length; i++) {
            _setHoldingCustomFee(_strategies[i], _holdings[i], _vals[i]);
        }
    }

    /**
     * @notice Sets a custom fee for a specific holding.
     * @param _strategy The address of the strategy.
     * @param _holding The address of the holding.
     * @param _val The custom fee to set.
     */
    function setHoldingCustomFee(address _strategy, address _holding, uint256 _val) external {
        _setHoldingCustomFee(_strategy, _holding, _val);
    }

    /**
     * @notice Retrieves the custom holding fee.
     * @param _strategy The address of the strategy.
     * @param _holding The address of the holding.
     * @return holding's custom fee or default.
     */
    function getHoldingFee(
        address _strategy,
        address _holding
    ) external view returns (uint256) {
        (uint256 defaultPerformanceFee,,) = _getStrategyManager().strategyInfo(address(_strategy));
        return holdingCustomFee[_strategy][_holding] == 0 ? defaultPerformanceFee : holdingCustomFee[_strategy][_holding];
    }

    /**
     * @notice Sets a custom fee for a specific holding.
     * @dev Only the owner of the contract is authorized to perform upgrades, ensuring that only authorized parties
     * @param _strategy The address of the strategy.
     * @param _holding The address of the holding.
     * @param _val The custom fee to set.
     */
    function _setHoldingCustomFee(address _strategy, address _holding, uint256 _val) private onlyOwner {
        require(_strategy != address(0), "3000");
        require(_holding != address(0), "3000");
        require(holdingCustomFee[_strategy][_holding] != _val, "3017");

        require(_val < manager.MAX_PERFORMANCE_FEE(), "3018");

        emit HoldingCustomFeeUpdated(_strategy, _holding, holdingCustomFee[_strategy][_holding], _val);
        holdingCustomFee[_strategy][_holding] = _val;
    }

    /**
     * @notice Retrieves the Strategy Manager Contract instance from the Manager Contract.
     * @return IStrategyManager The Strategy Manager contract instance.
     */
    function _getStrategyManager() internal view returns (IStrategyManager) {
        return IStrategyManager(manager.strategyManager());
    }
}
