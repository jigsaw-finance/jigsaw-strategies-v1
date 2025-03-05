// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IToken is IERC20 {
    function mint(address, uint256) external;
    function burnFrom(address, uint256) external;
}

interface ISavingModuleMin {
    function redeemFee() external view returns (uint256);
    function currentPrice() external view returns (uint256);
    function rusd() external view returns (IToken);
    function srusd() external view returns (IToken);
}
