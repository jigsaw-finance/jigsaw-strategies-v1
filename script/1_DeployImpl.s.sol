// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "./CommonStrategyScriptBase.s.sol";

/**
 * @title DeployImpl - Deploy various strategy contracts based on provided strategy names
 * @notice This contract allows the deployment of specific strategy implementations depending on the strategy name
 * provided during execution.
 * @dev This contract inherits from CommonStrategyScriptBase for shared functionality.
 */
contract DeployImpl is CommonStrategyScriptBase {
    /**
     * @notice Deploys the appropriate strategy implementation based on the provided strategy name.
     *
     * @dev This function uses keccak256 to compare the provided strategy name with pre-defined constants.
     * @dev If the strategy name does not match any of the known strategies, it reverts with "Unknown strategy".
     *
     * @param _strategy The name of the strategy to deploy. Must match one of the pre-defined constants:
     *        - `AAVE_STRATEGY` for AaveV3Strategy
     *        - `ION_STRATEGY` for IonStrategy
     *        - `PENDLE_STRATEGY` for PendleStrategy
     *        - `RESERVOIR_STRATEGY` for ReservoirSavingStrategy
     *        - `DINERO_STRATEGY` for DineroStrategy
     *
     * @return implementation The address of the deployed strategy contract.
     */
    function run(
        string memory _strategy
    ) external broadcast returns (address implementation) {
        if (keccak256(bytes(_strategy)) == AAVE_STRATEGY) return address(new AaveV3Strategy());
        if (keccak256(bytes(_strategy)) == PENDLE_STRATEGY) return address(new PendleStrategy());
        if (keccak256(bytes(_strategy)) == RESERVOIR_STRATEGY) return address(new ReservoirSavingStrategy());
        if (keccak256(bytes(_strategy)) == DINERO_STRATEGY) return address(new DineroStrategy());
        revert("Unknown strategy");
    }
}
