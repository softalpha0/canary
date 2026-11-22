// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PQC_VERIFY, PQC_KEY_STATUS} from "../src/interfaces/IQorePQC.sol";
import {PQAuth} from "../src/lib/PQAuth.sol";
import {MockPQCKeyStatus, MockPQCVerify} from "./mocks/MockPQC.sol";

/// @notice Installs the precompile mocks at the real addresses and offers fake ML-DSA keys and signatures.
abstract contract PQTestBase is Test {
    MockPQCKeyStatus internal keyStatus = MockPQCKeyStatus(PQC_KEY_STATUS);

    function _installPrecompiles() internal {
        vm.etch(PQC_KEY_STATUS, type(MockPQCKeyStatus).runtimeCode);
        vm.etch(PQC_VERIFY, type(MockPQCVerify).runtimeCode);
    }

    /// @dev Inactive precompile on-chain = success with empty data (SPIKE S3); etching empty code reproduces it.
    function _removePrecompiles() internal {
        vm.etch(PQC_KEY_STATUS, "");
        vm.etch(PQC_VERIFY, "");
    }

    /// @dev A deterministic 2,592-byte fake public key for `who`.
    function fakePubkey(address who) internal pure returns (bytes memory pk) {
        pk = new bytes(2592);
        bytes32 seed = keccak256(abi.encode("pk", who));
        for (uint256 i = 0; i < 2592; i += 32) {
            bytes32 w = keccak256(abi.encode(seed, i));
            for (uint256 j = 0; j < 32 && i + j < 2592; ++j) {
                pk[i + j] = w[j];
            }
        }
    }

    function registerKey(address who) internal {
        keyStatus.setKey(who, true, 1, fakePubkey(who), true);
    }

    /// @dev Fake ML-DSA signature accepted by MockPQCVerify for (pubkey, message).
    function fakeSign(bytes memory pubkey, bytes memory message) internal pure returns (bytes memory sig) {
        sig = new bytes(4627);
        bytes32 h = keccak256(abi.encodePacked(pubkey, message));
        assembly {
            mstore(add(sig, 32), h)
        }
    }

    /// @dev `who` signs digest `d` in RAW mode with their registered fake key.
    function pqSign(address who, bytes32 d) internal pure returns (bytes memory) {
        return fakeSign(fakePubkey(who), PQAuth.message(d, PQAuth.MODE_RAW));
    }
}
