// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

/// @notice The subset of CanaryRegistry that CoverPool reads.
interface ICanaryRegistry {
    /// @notice Whether canary `id` is dead and when it died (0 while alive).
    function isDead(uint256 id) external view returns (bool dead, uint64 deadAt);

    /// @notice Who proved canary `id`'s break (zero while alive).
    function reporterOf(uint256 id) external view returns (address);

    /// @notice Number of registered canaries.
    function count() external view returns (uint256);
}
