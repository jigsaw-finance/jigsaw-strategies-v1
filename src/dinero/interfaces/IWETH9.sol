// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Interface for WETH9
 */
interface IWETH9 is IERC20 {
    /**
     * @notice Deposit ether to get wrapped ether
     */
    function deposit() external payable;

    /**
     * @notice Withdraw wrapped ether to get ether
     */
    function withdraw(
        uint256
    ) external;
}
