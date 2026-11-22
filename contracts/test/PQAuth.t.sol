// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {PQAuth} from "../src/lib/PQAuth.sol";
import {PQTestBase} from "./PQTestBase.sol";

/// @notice Exposes PQAuth with an explicit-nonce consume path, as a pool would use it.
contract PQAuthHarness {
    error BadNonce(uint256 expected);

    mapping(address => uint256) public nonces;
    uint8 public immutable mode;

    constructor(uint8 mode_) {
        mode = mode_;
    }

    function digest(bytes32 action, address owner, uint256 nonce, uint256 deadline, bytes32 paramsHash)
        external
        view
        returns (bytes32)
    {
        return PQAuth.digest(address(this), action, owner, nonce, deadline, paramsHash);
    }

    function ownerKey(address owner) external view returns (bytes memory) {
        return PQAuth.ownerKey(owner);
    }

    function verify(address owner, bytes32 d, bytes calldata sig) external view {
        PQAuth.verify(owner, d, sig, mode);
    }

    function message(bytes32 d, uint8 m) external pure returns (bytes memory) {
        return PQAuth.message(d, m);
    }

    /// @dev Authorise and consume `nonce`, which must equal nonces[owner].
    function use(bytes32 action, address owner, uint256 nonce, uint256 deadline, bytes32 paramsHash, bytes calldata sig)
        external
    {
        if (nonce != nonces[owner]) revert BadNonce(nonces[owner]);
        PQAuth.authorize(address(this), action, owner, nonce, deadline, paramsHash, sig, mode);
        nonces[owner] = nonce + 1;
    }
}

contract PQAuthTest is PQTestBase {
    PQAuthHarness internal h;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    bytes32 internal constant ACTION = keccak256("CLAIM_PAYOUT");
    bytes32 internal paramsHash = keccak256(abi.encode(uint256(42), address(0xBEEF)));
    uint256 internal deadline;

    function setUp() public {
        _installPrecompiles();
        registerKey(alice);
        h = new PQAuthHarness(PQAuth.MODE_RAW);
        deadline = block.timestamp + 600;
    }

    function _sigFor(address signer, address owner, uint256 nonce) internal view returns (bytes memory) {
        return pqSign(signer, h.digest(ACTION, owner, nonce, deadline, paramsHash));
    }

    // ---- happy path, nonce and replay

    function test_validSignaturePasses_andConsumesNonce() public {
        bytes memory sig = _sigFor(alice, alice, 0);
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
        assertEq(h.nonces(alice), 1);
    }

    function test_replaySameNonce_revertsBadNonce() public {
        bytes memory sig = _sigFor(alice, alice, 0);
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
        vm.expectRevert(abi.encodeWithSelector(PQAuthHarness.BadNonce.selector, 1));
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
    }

    function test_replayWithNextNonce_revertsBadSignature() public {
        bytes memory sig = _sigFor(alice, alice, 0);
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        h.use(ACTION, alice, 1, deadline, paramsHash, sig);
    }

    // ---- every digest field matters

    function test_digestChangesWithEveryField() public {
        bytes32 base = h.digest(ACTION, alice, 0, deadline, paramsHash);
        assertNotEq(base, h.digest(ACTION, bob, 0, deadline, paramsHash), "owner");
        assertNotEq(base, h.digest(keccak256("SET_RATE"), alice, 0, deadline, paramsHash), "action");
        assertNotEq(base, h.digest(ACTION, alice, 1, deadline, paramsHash), "nonce");
        assertNotEq(base, h.digest(ACTION, alice, 0, deadline + 1, paramsHash), "deadline");
        assertNotEq(
            base, h.digest(ACTION, alice, 0, deadline, keccak256(abi.encode(uint256(43), address(0xBEEF)))), "param 1"
        );
        assertNotEq(
            base, h.digest(ACTION, alice, 0, deadline, keccak256(abi.encode(uint256(42), address(0xBEEE)))), "param 2"
        );
        PQAuthHarness other = new PQAuthHarness(PQAuth.MODE_RAW);
        assertNotEq(base, other.digest(ACTION, alice, 0, deadline, paramsHash), "contract");
        vm.chainId(1);
        assertNotEq(base, h.digest(ACTION, alice, 0, deadline, paramsHash), "chainId");
    }

    function test_signatureForOtherContract_fails() public {
        PQAuthHarness other = new PQAuthHarness(PQAuth.MODE_RAW);
        bytes memory sig = pqSign(alice, other.digest(ACTION, alice, 0, deadline, paramsHash));
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
    }

    function test_signatureOnOtherChain_fails() public {
        bytes memory sig = _sigFor(alice, alice, 0);
        vm.chainId(1);
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
    }

    function test_signatureByAnotherKey_fails() public {
        registerKey(bob);
        bytes memory sig = _sigFor(bob, alice, 0); // bob signs alice's action
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
    }

    function test_tamperedParams_fails() public {
        bytes memory sig = _sigFor(alice, alice, 0);
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        h.use(ACTION, alice, 0, deadline, keccak256("other"), sig);
    }

    // ---- deadline

    function test_expiredDeadline_reverts() public {
        bytes memory sig = _sigFor(alice, alice, 0);
        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQExpired.selector, deadline));
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
    }

    function test_deadlineExactlyNow_passes() public {
        bytes memory sig = _sigFor(alice, alice, 0);
        vm.warp(deadline);
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
    }

    // ---- key status checks

    function test_keyNotRegistered_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQKeyNotRegistered.selector, bob));
        h.ownerKey(bob);
    }

    function test_keyNotProven_reverts() public {
        keyStatus.setKey(bob, true, 1, fakePubkey(bob), false);
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQKeyNotProven.selector, bob));
        h.ownerKey(bob);
    }

    function test_wrongAlgorithm_reverts() public {
        keyStatus.setKey(bob, true, 2, fakePubkey(bob), true);
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQWrongAlgorithm.selector, bob, uint8(2)));
        h.ownerKey(bob);
    }

    function test_wrongPubkeyLength_reverts() public {
        keyStatus.setKey(bob, true, 1, new bytes(2591), true);
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQBadPubkeyLength.selector, bob, uint256(2591)));
        h.ownerKey(bob);
    }

    function test_ownerKey_returnsRegisteredKey() public view {
        assertEq(keccak256(h.ownerKey(alice)), keccak256(fakePubkey(alice)));
    }

    // ---- signature checks

    function test_wrongSignatureLength_reverts() public {
        bytes32 d = h.digest(ACTION, alice, 0, deadline, paramsHash);
        bytes memory sig = pqSign(alice, d);
        bytes memory short = new bytes(4626);
        for (uint256 i = 0; i < 4626; ++i) {
            short[i] = sig[i];
        }
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        h.verify(alice, d, short);
        bytes memory long = bytes.concat(sig, hex"00");
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        h.verify(alice, d, long);
    }

    // ---- fail closed

    function test_absentPrecompiles_failClosed() public {
        bytes memory sig = _sigFor(alice, alice, 0);
        _removePrecompiles();
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        h.ownerKey(alice);
    }

    function test_absentVerifyOnly_failsClosed() public {
        bytes memory sig = _sigFor(alice, alice, 0);
        vm.etch(address(0x0a01), "");
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        h.use(ACTION, alice, 0, deadline, paramsHash, sig);
    }

    // ---- modes

    function test_messageRaw_isDigestBytes() public view {
        bytes32 d = keccak256("d");
        assertEq(h.message(d, PQAuth.MODE_RAW), abi.encodePacked(d));
    }

    function test_messageQoreX_isPrefixedLowercaseHex() public view {
        bytes32 d = 0x8404311f59f0ac17137acf43cf0fa749412488e891cdb0bc48c9915252776ecc;
        assertEq(
            h.message(d, PQAuth.MODE_QOREX),
            bytes("qorechain-msg-v1|qorechain-diana|0x8404311f59f0ac17137acf43cf0fa749412488e891cdb0bc48c9915252776ecc")
        );
    }

    function test_qorexModeHarness_verifiesPrefixedMessage() public {
        PQAuthHarness q = new PQAuthHarness(PQAuth.MODE_QOREX);
        bytes32 d = q.digest(ACTION, alice, 0, deadline, paramsHash);
        bytes memory sig = fakeSign(fakePubkey(alice), PQAuth.message(d, PQAuth.MODE_QOREX));
        q.use(ACTION, alice, 0, deadline, paramsHash, sig);
        // a RAW-mode signature is rejected by a QOREX-mode verifier
        bytes32 d1 = q.digest(ACTION, alice, 1, deadline, paramsHash);
        bytes memory rawSig = pqSign(alice, d1);
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        q.use(ACTION, alice, 1, deadline, paramsHash, rawSig);
    }

    function test_unknownMode_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQBadMode.selector, uint8(2)));
        h.message(bytes32(0), 2);
    }

    // ---- exported test vector (scripts/lib/digest.ts and the app are tested against it)

    function test_exportDigestVector() public {
        vm.chainId(9800);
        address verifying = 0x00000000000000000000000000000000C0FfeE00;
        bytes32 action = keccak256("CLAIM_PAYOUT");
        address owner = 0x4DF6ED71f117dfFfB2e64Dab748A061f3A71e52B;
        uint256 nonce = 7;
        uint256 dl = 1767225600;
        bytes32 ph = keccak256(abi.encode(uint256(42), address(0x000000000000000000000000000000000000bEEF)));
        bytes32 d = PQAuth.digest(verifying, action, owner, nonce, dl, ph);
        // Pinned value: any change to the digest layout must be deliberate.
        assertEq(d, VECTOR_DIGEST);

        string memory o = "v";
        vm.serializeString(o, "description", "PQAuth.digest test vector (contracts/test/PQAuth.t.sol)");
        vm.serializeUint(o, "chainId", 9800);
        vm.serializeAddress(o, "verifyingContract", verifying);
        vm.serializeString(o, "actionName", "CLAIM_PAYOUT");
        vm.serializeBytes32(o, "action", action);
        vm.serializeAddress(o, "owner", owner);
        vm.serializeUint(o, "nonce", nonce);
        vm.serializeUint(o, "deadline", dl);
        vm.serializeString(o, "paramsAbi", "(uint256,address)");
        vm.serializeUint(o, "paramPolicyId", 42);
        vm.serializeAddress(o, "paramRecipient", address(0xbEEF));
        vm.serializeBytes32(o, "paramsHash", ph);
        vm.serializeBytes32(o, "domainTag", PQAuth.DOMAIN_TAG);
        string memory json = vm.serializeBytes32(o, "digest", d);
        vm.writeJson(json, "./test/vectors/digest.json");
    }

    bytes32 internal constant VECTOR_DIGEST = 0x8ed4deba70d85ec6e00048ba0499f1e833c6d1e4c95133c89ee234e55979e47d;
}
