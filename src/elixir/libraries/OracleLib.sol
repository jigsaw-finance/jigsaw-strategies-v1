// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IOracle } from "@jigsaw/src/interfaces/oracle/IOracle.sol";
import { GenericUniswapV3Oracle } from "@jigsaw/src/oracles/uniswap/GenericUniswapV3Oracle.sol";

/**
 * @title OracleLib
 * @notice Library for deploying Uniswap V3 oracles.
 * @dev Provides helper functions to deploy and initialize oracle contracts.
 */
library OracleLib {
    /**
     * @notice Deploys a new GenericUniswapV3Oracle contract.
     * @dev This function creates a new instance of GenericUniswapV3Oracle with the provided parameters.
     * @param _initialOwner The address to be set as the initial owner of the oracle.
     * @param _underlying The address of the underlying asset for which the oracle provides price data.
     * @param _quoteToken The address of the quote token used in the Uniswap V3 pools.
     * @param _uniswapV3Pools An array of Uniswap V3 pool addresses used for price aggregation.
     * @return Returns the address of the newly deployed oracle as an IOracle interface.
     */
    function deployUniswapOracle(
        address _initialOwner,
        address _underlying,
        address _quoteToken,
        address[] memory _uniswapV3Pools
    ) public returns (IOracle) {
        return IOracle(
            new GenericUniswapV3Oracle({
                _initialOwner: _initialOwner,
                _underlying: _underlying,
                _quoteToken: _quoteToken,
                _uniswapV3Pools: _uniswapV3Pools
            })
        );
    }
}
