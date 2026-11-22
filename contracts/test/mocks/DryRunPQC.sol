// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

/// @notice Deploy rehearsal only (local anvil fork has no QoreChain precompiles): reports every account as having a
///         registered, proven ML-DSA-87 key so CoverPool's constructor admin check passes on the fork.
contract DryRunPQCKeyStatus {
    function pqcKeyStatus(address) external pure returns (bool, uint8, bytes memory, bool) {
        return (true, 1, new bytes(2592), true);
    }
}
