// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IOracle } from "@jigsaw/src/interfaces/oracle/IOracle.sol";

contract SampleStrategyOracle is IOracle {
    uint256 public someNo;
    uint256 public price;
    bool public updated = true;

    constructor() {
        price = 1e18;
    }

    function setPrice(
        uint256 _price
    ) external {
        price = _price;
    }

    function setPriceForLiquidation() external {
        price = 8e17;
    }

    function setPriceForPossibleLiquidation() external {
        price = 8e17;
    }

    function setAVeryLowPrice() external {
        price = 1e17;
    }

    function setRateTo0() external {
        price = 0;
    }

    function setUpdatedToFalse() external {
        updated = false;
    }

    function peek(
        bytes calldata
    ) external view override returns (bool success, uint256 rate) {
        return (updated, price);
    }
    function underlying() external view returns (address)
    {
        return address(this);
    }

    function symbol() external view override returns (string memory)
    {
        return "SSO";
    }

    function name() external view override returns (string memory)
    {
        return "Sample Strategy Oracle";
    }
}
