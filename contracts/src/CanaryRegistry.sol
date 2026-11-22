// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {ICanaryRegistry} from "./interfaces/ICanaryRegistry.sol";

/// @title CanaryRegistry
/// @notice Records canaries: secp256k1 public keys whose private key nobody knows. The real canary is derived
///         from a public phrase with RFC 9380 hash-to-curve. A valid ECDSA signature from a canary key is public
///         proof that ECDSA on secp256k1 is broken; the first one submitted marks that canary dead.
/// @dev Immutable after deployment. Holds no funds. No admin.
contract CanaryRegistry is ICanaryRegistry {
    struct Canary {
        address addr; // EVM address of the canary public key
        bool isTest; // true = test canary (key held by the team, for demos)
        uint64 deadAt; // 0 while alive
        address reporter; // who proved the break
        string label; // e.g. "Canary #1 (secp256k1)"
        string phrase; // hash-to-curve input message; "" for the test canary
        string dst; // hash-to-curve domain separation tag; "" for the test canary
    }

    /// @notice Tag mixed into every break digest.
    bytes32 public constant BREAK_TAG = keccak256("Canary.break.v1");

    /// @notice All canaries. Index 0 = real canary, index 1 = test canary.
    Canary[] public canaries;

    event CanaryDied(uint256 indexed id, address indexed reporter, uint64 deadAt, bool isTest);

    error UnknownCanary(uint256 id);
    error AlreadyDead(uint256 id);
    error InvalidBreakSignature();
    error ZeroReporter();
    error InvalidCanary(uint256 index);
    error NoCanaries();

    /// @notice Register the initial canaries. Each must have a non-zero address, be alive and have no reporter.
    constructor(Canary[] memory initial) {
        if (initial.length == 0) revert NoCanaries();
        for (uint256 i = 0; i < initial.length; ++i) {
            Canary memory c = initial[i];
            if (c.addr == address(0) || c.deadAt != 0 || c.reporter != address(0)) revert InvalidCanary(i);
            canaries.push(c);
        }
    }

    /// @notice The 32-byte digest a canary key must sign (raw, no Ethereum message prefix) to prove a break.
    /// @dev Binding `reporter` means a copied proof cannot redirect the bounty; binding chain and contract
    ///      means a proof cannot be replayed elsewhere.
    function breakDigest(uint256 id, address reporter) public view returns (bytes32) {
        return keccak256(abi.encode(BREAK_TAG, block.chainid, address(this), id, reporter));
    }

    /// @notice Submit a break proof for canary `id`. Anyone may call; `reporter` receives the bounty.
    /// @param v Recovery id (27 or 28). @param r Signature r. @param s Signature s.
    function reportBreak(uint256 id, address reporter, uint8 v, bytes32 r, bytes32 s) external {
        Canary storage c = _canary(id);
        if (c.deadAt != 0) revert AlreadyDead(id);
        if (reporter == address(0)) revert ZeroReporter();
        address signer = ecrecover(breakDigest(id, reporter), v, r, s);
        if (signer == address(0) || signer != c.addr) revert InvalidBreakSignature();
        c.deadAt = uint64(block.timestamp);
        c.reporter = reporter;
        emit CanaryDied(id, reporter, c.deadAt, c.isTest);
    }

    /// @inheritdoc ICanaryRegistry
    function isDead(uint256 id) external view returns (bool dead, uint64 deadAt) {
        deadAt = _canary(id).deadAt;
        dead = deadAt != 0;
    }

    /// @inheritdoc ICanaryRegistry
    function reporterOf(uint256 id) external view returns (address) {
        return _canary(id).reporter;
    }

    /// @inheritdoc ICanaryRegistry
    function count() external view returns (uint256) {
        return canaries.length;
    }

    /// @notice Full record of canary `id` (the public getter omits nothing but returns a tuple).
    function getCanary(uint256 id) external view returns (Canary memory) {
        return _canary(id);
    }

    function _canary(uint256 id) internal view returns (Canary storage) {
        if (id >= canaries.length) revert UnknownCanary(id);
        return canaries[id];
    }
}
