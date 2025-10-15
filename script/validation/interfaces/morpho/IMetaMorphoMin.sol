// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

interface IMetaMorphoMin {
    /// @notice The address of the curator.
    function curator() external view returns (address);

    /// @notice Stores whether an address is an allocator or not.
    function isAllocator(
        address target
    ) external view returns (bool);

    /// @notice The current guardian. Can be set even without the timelock set.
    function guardian() external view returns (address);

    /// @notice Stores the missing assets due to realized bad debt or forced market removal.
    /// @dev In order to cover those lost assets, it is advised to supply on behalf of address(1) on the vault
    /// (canonical method).
    function lostAssets() external view returns (uint256);
}
