// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CanaryRegistry} from "../src/CanaryRegistry.sol";

contract CanaryRegistryTest is Test {
    CanaryRegistry internal reg;
    uint256 internal testCanaryKey = 0xC0FFEE;
    address internal testCanary;
    /// @dev RFC 9380 hash_to_curve("QoreChain Canary 2026 #1", DST "CANARY-V1-QORECHAIN_XMD:SHA-256_SSWU_RO_")
    ///      → keccak256(X‖Y)[12:], from scripts/derive-canary.ts (deployments/canary.json).
    address internal constant REAL_CANARY = 0xcE071018914e03Cb1eC2aD9e3EbbA7af87dB305D;
    address internal realCanary = REAL_CANARY;
    address internal reporter = makeAddr("reporter");

    event CanaryDied(uint256 indexed id, address indexed reporter, uint64 deadAt, bool isTest);

    function setUp() public {
        testCanary = vm.addr(testCanaryKey);
        reg = new CanaryRegistry(_initial(realCanary, testCanary));
    }

    function _initial(address real, address test) internal pure returns (CanaryRegistry.Canary[] memory c) {
        c = new CanaryRegistry.Canary[](2);
        c[0] = CanaryRegistry.Canary(
            real,
            false,
            0,
            address(0),
            "Canary #1 (secp256k1)",
            "QoreChain Canary 2026 #1",
            "CANARY-V1-QORECHAIN_XMD:SHA-256_SSWU_RO_"
        );
        c[1] = CanaryRegistry.Canary(test, true, 0, address(0), "TEST canary", "", "");
    }

    function _sign(uint256 key, bytes32 d) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        (v, r, s) = vm.sign(key, d);
    }

    // ---- constructor

    function test_constructor_storesCanaries() public view {
        assertEq(reg.count(), 2);
        CanaryRegistry.Canary memory c0 = reg.getCanary(0);
        assertEq(c0.addr, realCanary);
        assertFalse(c0.isTest);
        assertEq(c0.phrase, "QoreChain Canary 2026 #1");
        assertEq(c0.dst, "CANARY-V1-QORECHAIN_XMD:SHA-256_SSWU_RO_");
        CanaryRegistry.Canary memory c1 = reg.getCanary(1);
        assertEq(c1.addr, testCanary);
        assertTrue(c1.isTest);
        (bool dead, uint64 at) = reg.isDead(1);
        assertFalse(dead);
        assertEq(at, 0);
        assertEq(reg.reporterOf(1), address(0));
    }

    function test_constructor_rejectsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(CanaryRegistry.InvalidCanary.selector, 1));
        new CanaryRegistry(_initial(realCanary, address(0)));
    }

    function test_constructor_rejectsDeadOrReported() public {
        CanaryRegistry.Canary[] memory c = _initial(realCanary, testCanary);
        c[0].deadAt = 1;
        vm.expectRevert(abi.encodeWithSelector(CanaryRegistry.InvalidCanary.selector, 0));
        new CanaryRegistry(c);
        c = _initial(realCanary, testCanary);
        c[1].reporter = reporter;
        vm.expectRevert(abi.encodeWithSelector(CanaryRegistry.InvalidCanary.selector, 1));
        new CanaryRegistry(c);
    }

    function test_constructor_rejectsEmpty() public {
        vm.expectRevert(CanaryRegistry.NoCanaries.selector);
        new CanaryRegistry(new CanaryRegistry.Canary[](0));
    }

    // ---- reportBreak

    function test_reportBreak_validSignature_marksDead() public {
        vm.warp(1_800_000_000);
        (uint8 v, bytes32 r, bytes32 s) = _sign(testCanaryKey, reg.breakDigest(1, reporter));
        vm.expectEmit(address(reg));
        emit CanaryDied(1, reporter, 1_800_000_000, true);
        reg.reportBreak(1, reporter, v, r, s);
        (bool dead, uint64 at) = reg.isDead(1);
        assertTrue(dead);
        assertEq(at, 1_800_000_000);
        assertEq(reg.reporterOf(1), reporter);
        // the real canary is unaffected
        (dead,) = reg.isDead(0);
        assertFalse(dead);
    }

    function test_reportBreak_anyoneCanSubmit() public {
        (uint8 v, bytes32 r, bytes32 s) = _sign(testCanaryKey, reg.breakDigest(1, reporter));
        vm.prank(makeAddr("relayer"));
        reg.reportBreak(1, reporter, v, r, s);
        assertEq(reg.reporterOf(1), reporter);
    }

    function test_reportBreak_wrongSigner_reverts() public {
        (uint8 v, bytes32 r, bytes32 s) = _sign(0xBAD, reg.breakDigest(1, reporter));
        vm.expectRevert(CanaryRegistry.InvalidBreakSignature.selector);
        reg.reportBreak(1, reporter, v, r, s);
    }

    function test_reportBreak_signatureForAnotherReporter_reverts() public {
        (uint8 v, bytes32 r, bytes32 s) = _sign(testCanaryKey, reg.breakDigest(1, reporter));
        vm.expectRevert(CanaryRegistry.InvalidBreakSignature.selector);
        reg.reportBreak(1, makeAddr("thief"), v, r, s);
    }

    function test_reportBreak_signatureForAnotherCanaryId_reverts() public {
        (uint8 v, bytes32 r, bytes32 s) = _sign(testCanaryKey, reg.breakDigest(0, reporter));
        vm.expectRevert(CanaryRegistry.InvalidBreakSignature.selector);
        reg.reportBreak(1, reporter, v, r, s);
        // and the test key cannot kill the real canary
        vm.expectRevert(CanaryRegistry.InvalidBreakSignature.selector);
        reg.reportBreak(0, reporter, v, r, s);
    }

    function test_reportBreak_secondReport_revertsAlreadyDead() public {
        (uint8 v, bytes32 r, bytes32 s) = _sign(testCanaryKey, reg.breakDigest(1, reporter));
        reg.reportBreak(1, reporter, v, r, s);
        vm.expectRevert(abi.encodeWithSelector(CanaryRegistry.AlreadyDead.selector, 1));
        reg.reportBreak(1, reporter, v, r, s);
    }

    function test_reportBreak_unknownId_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(CanaryRegistry.UnknownCanary.selector, 2));
        reg.reportBreak(2, reporter, 27, bytes32(0), bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(CanaryRegistry.UnknownCanary.selector, 5));
        reg.isDead(5);
        vm.expectRevert(abi.encodeWithSelector(CanaryRegistry.UnknownCanary.selector, 5));
        reg.reporterOf(5);
    }

    function test_reportBreak_zeroReporter_reverts() public {
        (uint8 v, bytes32 r, bytes32 s) = _sign(testCanaryKey, reg.breakDigest(1, address(0)));
        vm.expectRevert(CanaryRegistry.ZeroReporter.selector);
        reg.reportBreak(1, address(0), v, r, s);
    }

    function test_reportBreak_malformedV_reverts() public {
        (, bytes32 r, bytes32 s) = _sign(testCanaryKey, reg.breakDigest(1, reporter));
        vm.expectRevert(CanaryRegistry.InvalidBreakSignature.selector);
        reg.reportBreak(1, reporter, 29, r, s); // ecrecover returns address(0)
        vm.expectRevert(CanaryRegistry.InvalidBreakSignature.selector);
        reg.reportBreak(1, reporter, 0, r, s);
    }

    function test_reportBreak_zeroSignature_reverts() public {
        vm.expectRevert(CanaryRegistry.InvalidBreakSignature.selector);
        reg.reportBreak(1, reporter, 27, bytes32(0), bytes32(0));
    }

    function test_breakDigest_changesWithChainId() public {
        bytes32 a = reg.breakDigest(1, reporter);
        vm.chainId(1);
        assertNotEq(a, reg.breakDigest(1, reporter));
    }

    function test_reportBreak_proofFromOtherChain_reverts() public {
        (uint8 v, bytes32 r, bytes32 s) = _sign(testCanaryKey, reg.breakDigest(1, reporter));
        vm.chainId(1);
        vm.expectRevert(CanaryRegistry.InvalidBreakSignature.selector);
        reg.reportBreak(1, reporter, v, r, s);
    }

    function test_realCanary_equalsDerivedAddress() public view {
        string memory json = vm.readFile("../deployments/canary.json");
        assertEq(vm.parseJsonAddress(json, ".address"), REAL_CANARY, "canary.json");
        assertEq(vm.parseJsonString(json, ".msg"), "QoreChain Canary 2026 #1");
        assertEq(vm.parseJsonString(json, ".dst"), "CANARY-V1-QORECHAIN_XMD:SHA-256_SSWU_RO_");
        assertEq(reg.getCanary(0).addr, REAL_CANARY, "registry canary #0");
        // the derived point's address is keccak256(X || Y)[12:]
        bytes memory xy = abi.encodePacked(vm.parseJsonBytes32(json, ".x"), vm.parseJsonBytes32(json, ".y"));
        assertEq(address(uint160(uint256(keccak256(xy)))), REAL_CANARY, "keccak(X||Y)");
    }

    function test_breakDigest_matchesSpec() public view {
        assertEq(
            reg.breakDigest(1, reporter),
            keccak256(abi.encode(keccak256("Canary.break.v1"), block.chainid, address(reg), uint256(1), reporter))
        );
    }
}
