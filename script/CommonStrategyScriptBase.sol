// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { Script, stdJson as StdJson } from "forge-std/Script.sol";

contract CommonStrategyScriptBase is Script {
    using StdJson for string;

    modifier broadcast(
        uint256 _pk
    ) {
        vm.startBroadcast(_pk);
        _;
        vm.stopBroadcast();
    }
    /**
     * @notice Address of the owner
     */

    address public OWNER = 0x3412d07beF5d0DcDb942aC1765D0b8f19D8CA2C4;

    /**
     * @notice Address of the Jigsaw's Manager Container Contract
     */
    address public MANAGER_CONTAINER = 0xB23B5406c67b31DB4BC223afa20fc75ebBa50CA9;

    /**
     * @notice Address of the Staker Factory Contract
     */
    address public STAKER_FACTORY = 0xE41fCFCe505457DB0DF31aD6D3D20606D8Fb1c6E;

    /**
     * @notice Address of Jigsaw's reward tokens
     */
    address public jREWARDS = 0x371BC93e9661d445fC046918231483faDF1Dbd96;
}
