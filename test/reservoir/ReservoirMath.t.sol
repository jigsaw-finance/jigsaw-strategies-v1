// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReservoirSavingStrategy } from "src/reservoir/ReservoirSavingStrategy.sol";

contract ReservoirMath is Test, ReservoirSavingStrategy {
    function test_getAssetsToWithdraw(uint256 shares, uint256 price) public {
        uint256 redeemFee = 5000;

        shares = bound(shares, 1e18, 1e22);
        price = bound(price, 1e8, 1e8 + 5e7);

        // JigSaw shares -> assets
        uint256 assetsToWithdraw = _getAssetsToWithdraw(shares, price, redeemFee);

        // Reservoir assets -> shares
        uint256 burnAmount = Math.ceilDiv(assetsToWithdraw * 1e8, price);
        uint256 srusdBurned = (burnAmount * (1e6 + redeemFee)) / 1e6;

        assertLe(srusdBurned, shares, "Burned more srUSD than internal shares");
    }
}
