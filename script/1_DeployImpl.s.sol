// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "./CommonStrategyScriptBase.sol";

contract DeployImpl is CommonStrategyScriptBase {
    /**
     * @notice Deploys the appropriate strategy implementation based on the provided strategy name
     * @param _strategy The strategy name to deploy
     * @return The address of the deployed strategy contract
     */
    function run(
        string memory _strategy
    ) external broadcast returns (address) {
        if (keccak256(bytes(_strategy)) == AAVE_STRATEGY) return address(new AaveV3Strategy());
        if (keccak256(bytes(_strategy)) == ION_STRATEGY) return address(new IonStrategy());
        if (keccak256(bytes(_strategy)) == PENDLE_STRATEGY) return address(new PendleStrategy());
        if (keccak256(bytes(_strategy)) == RESERVOIR_STRATEGY) return address(new ReservoirStablecoinStrategy());
        if (keccak256(bytes(_strategy)) == DINERO_STRATEGY) return address(new DineroStrategy());
        revert("Unknown strategy");
    }
}
