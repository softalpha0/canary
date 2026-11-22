// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

/// @notice Stand-in for the pqcKeyStatus precompile, etched at 0x…0a02. Storage lives at the etched address.
contract MockPQCKeyStatus {
    struct Key {
        bool registered;
        uint8 algorithmId;
        bytes pubkey;
        bool proven;
    }

    mapping(address => Key) internal keys;

    function setKey(address account, bool registered, uint8 algorithmId, bytes calldata pubkey, bool proven) external {
        keys[account] = Key(registered, algorithmId, pubkey, proven);
    }

    function pqcKeyStatus(address account) external view returns (bool, uint8, bytes memory, bool) {
        Key storage k = keys[account];
        return (k.registered, k.algorithmId, k.pubkey, k.proven);
    }
}

/// @notice Stand-in for the pqcVerify precompile, etched at 0x…0a01. Deterministic fake scheme (plan 07):
///         valid iff the signature is 4,627 bytes and its first 32 bytes equal keccak256(pubkey ‖ message).
contract MockPQCVerify {
    function pqcVerify(bytes calldata pubkey, bytes calldata signature, bytes calldata message)
        external
        pure
        returns (bool)
    {
        if (signature.length != 4627) return false;
        return bytes32(signature[0:32]) == keccak256(abi.encodePacked(pubkey, message));
    }
}
