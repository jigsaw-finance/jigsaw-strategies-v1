// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { GenericUniswapV3Oracle } from "@jigsaw/src/oracles/uniswap/GenericUniswapV3Oracle.sol";
import { IOracle } from "@jigsaw/src/interfaces/oracle/IOracle.sol";

library StrategyOracleLib {
    /**
     * @notice Returns the IOracle of the strategy oracle.
     * @dev This function is used to retrieve the address of the strategy oracle, which is responsible for providing
     * price feeds and other relevant data for strategies.
     * @return The IOracle of the strategy oracle.
     */
    function getStrategyOracle(
        address _initialOwner,
        address _underlying,
        address _quoteToken,
        address _quoteTokenOracle,
        address[] memory _uniswapV3Pools
    ) public returns (IOracle) {
        return IOracle(
            new GenericUniswapV3Oracle({
                _initialOwner: _initialOwner,
                _underlying: _underlying,
                _quoteToken: _quoteToken,
                _quoteTokenOracle: _quoteTokenOracle,
                _uniswapV3Pools: _uniswapV3Pools
            }));
    }
}