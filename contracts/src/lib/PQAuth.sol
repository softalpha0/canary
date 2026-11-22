// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {PQC_VERIFY, PQC_KEY_STATUS, IPQCVerify, IPQCKeyStatus} from "../interfaces/IQorePQC.sol";

/// @title PQAuth
/// @notice Post-quantum action authorisation: an action is approved only by an ML-DSA-87 signature from the
///         owner's registered (and possession-proven) key, checked on-chain by QoreChain's `pqcVerify`.
/// @dev Fails closed: if either precompile is inactive (empty returndata) every check reverts.
///      Nonce storage and consumption belong to the calling contract (consume before any value transfer).
library PQAuth {
    /// @notice Domain tag mixed into every action digest.
    bytes32 internal constant DOMAIN_TAG = keccak256("Canary.v1");
    /// @notice pqcVerify receives the raw 32 digest bytes (proven in SPIKE S3 Track B).
    uint8 internal constant MODE_RAW = 0;
    /// @notice pqcVerify receives QoreX's prefixed message (SPIKE S3 Track A; not proven, not deployed).
    uint8 internal constant MODE_QOREX = 1;
    /// @notice ML-DSA-87 algorithm id in QoreChain's PQC module.
    uint8 internal constant ALGO_ML_DSA_87 = 1;
    uint256 internal constant PUBKEY_LENGTH = 2592;
    uint256 internal constant SIG_LENGTH = 4627;

    error PQPrecompileUnavailable();
    error PQKeyNotRegistered(address owner);
    error PQKeyNotProven(address owner);
    error PQWrongAlgorithm(address owner, uint8 algorithmId);
    error PQBadPubkeyLength(address owner, uint256 length);
    error PQBadSignature();
    error PQExpired(uint256 deadline);
    error PQBadMode(uint8 mode);

    /// @notice The 32-byte digest the owner's ML-DSA key signs for one action.
    function digest(
        address verifyingContract,
        bytes32 action,
        address owner,
        uint256 nonce,
        uint256 deadline,
        bytes32 paramsHash
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TAG, block.chainid, verifyingContract, action, owner, nonce, deadline, paramsHash)
        );
    }

    /// @notice The owner's registered ML-DSA-87 public key. Reverts unless registered, ML-DSA-87,
    ///         possession-proven and exactly 2,592 bytes.
    function ownerKey(address owner) internal view returns (bytes memory pubkey) {
        (bool ok, bytes memory ret) = PQC_KEY_STATUS.staticcall(abi.encodeCall(IPQCKeyStatus.pqcKeyStatus, (owner)));
        if (!ok || ret.length < 128) revert PQPrecompileUnavailable();
        bool registered;
        uint8 algorithmId;
        bool proven;
        (registered, algorithmId, pubkey, proven) = abi.decode(ret, (bool, uint8, bytes, bool));
        if (!registered) revert PQKeyNotRegistered(owner);
        if (algorithmId != ALGO_ML_DSA_87) revert PQWrongAlgorithm(owner, algorithmId);
        if (!proven) revert PQKeyNotProven(owner);
        if (pubkey.length != PUBKEY_LENGTH) revert PQBadPubkeyLength(owner, pubkey.length);
    }

    /// @notice Revert unless `sig` is the owner's valid ML-DSA-87 signature over digest `d` (in `mode`).
    function verify(address owner, bytes32 d, bytes calldata sig, uint8 mode) internal view {
        if (sig.length != SIG_LENGTH) revert PQBadSignature();
        bytes memory pubkey = ownerKey(owner);
        (bool ok, bytes memory ret) =
            PQC_VERIFY.staticcall(abi.encodeCall(IPQCVerify.pqcVerify, (pubkey, sig, message(d, mode))));
        if (!ok || ret.length < 32) revert PQPrecompileUnavailable();
        if (!abi.decode(ret, (bool))) revert PQBadSignature();
    }

    /// @notice Check the deadline, build the digest and verify the owner's signature. Returns the digest.
    function authorize(
        address verifyingContract,
        bytes32 action,
        address owner,
        uint256 nonce,
        uint256 deadline,
        bytes32 paramsHash,
        bytes calldata sig,
        uint8 mode
    ) internal view returns (bytes32 d) {
        if (block.timestamp > deadline) revert PQExpired(deadline);
        d = digest(verifyingContract, action, owner, nonce, deadline, paramsHash);
        verify(owner, d, sig, mode);
    }

    /// @notice The exact bytes passed to pqcVerify as `message` for digest `d`.
    function message(bytes32 d, uint8 mode) internal pure returns (bytes memory) {
        if (mode == MODE_RAW) return abi.encodePacked(d);
        if (mode == MODE_QOREX) return bytes.concat(bytes("qorechain-msg-v1|qorechain-diana|"), _hex0x(d));
        revert PQBadMode(mode);
    }

    /// @dev Lowercase "0x"-prefixed hex of `d` (66 ASCII bytes): the expected QoreX encoding (unproven).
    function _hex0x(bytes32 d) private pure returns (bytes memory out) {
        bytes16 symbols = "0123456789abcdef";
        out = new bytes(66);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = 0; i < 32; ++i) {
            out[2 + 2 * i] = symbols[uint8(d[i]) >> 4];
            out[3 + 2 * i] = symbols[uint8(d[i]) & 0x0f];
        }
    }
}
