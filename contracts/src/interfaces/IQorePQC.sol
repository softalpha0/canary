// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

/// @dev QoreChain PQC precompiles (docs.qorechain.io → EVM precompiles). Active on testnet only;
///      an inactive precompile address returns success with EMPTY data (verified in SPIKE S3).
address constant PQC_VERIFY = 0x0000000000000000000000000000000000000a01;
address constant PQC_KEY_STATUS = 0x0000000000000000000000000000000000000a02;

/// @notice ML-DSA-87 signature verification precompile at 0x…0a01.
interface IPQCVerify {
    /// @notice Verify an ML-DSA-87 (FIPS 204, pure, empty context) signature over raw `message` bytes.
    /// @dev pubkey 2,592 bytes, signature 4,627 bytes. Returns false on bad input; does not revert.
    function pqcVerify(bytes calldata pubkey, bytes calldata signature, bytes calldata message)
        external
        view
        returns (bool valid);
}

/// @notice Registered PQC key lookup precompile at 0x…0a02.
interface IPQCKeyStatus {
    /// @notice The account's registered PQC key. algorithmId 1 = ML-DSA-87.
    /// @dev possessionProven is optional at registration; Canary always requires it.
    function pqcKeyStatus(address account)
        external
        view
        returns (bool registered, uint8 algorithmId, bytes memory pubkey, bool possessionProven);
}
