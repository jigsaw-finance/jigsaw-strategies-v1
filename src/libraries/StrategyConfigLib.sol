// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IReceiptTokenFactory } from "@jigsaw/src/interfaces/core/IReceiptTokenFactory.sol";
import { IStrategyManager } from "@jigsaw/src/interfaces/core/IStrategyManager.sol";

/**
 * @title Strategy Configuration Library
 *
 * @notice This library provides functions for configuring strategies, specifically deploying receipt tokens and
 * associated components.
 *
 * @dev The library is designed to work with the receipt token factory, allowing for the creation of receipt tokens with
 * customizable names and symbols. It is intended for internal use within smart contracts to streamline the deployment
 * and configuration of strategies.
 */
library StrategyConfigLib {
    /**
     * @notice Deploys the receipt token associated with this strategy.
     *
     * @dev This function uses the receipt token factory to create a new receipt token with the provided name and
     * symbol. The newly created token will have the current contract as its minter and the _owner as its owner.
     *
     * @param _initialOwner The address of the receipt token's owner.
     * @param _receiptTokenFactory The address of the receipt token factory contract.
     * @param _receiptTokenName The name of the receipt token to be created.
     * @param _receiptTokenSymbol The symbol of the receipt token to be created.
     *
     * @return receiptToken The address of the newly created receipt token contract.
     */
    function configStrategy(
        address _initialOwner,
        address _receiptTokenFactory,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) internal returns (address receiptToken) {
        receiptToken = IReceiptTokenFactory(_receiptTokenFactory).createReceiptToken({
            _name: _receiptTokenName,
            _symbol: _receiptTokenSymbol,
            _minter: address(this),
            _owner: _initialOwner
        });
    }
}
