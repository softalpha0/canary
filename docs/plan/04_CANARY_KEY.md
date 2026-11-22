# 04 — The Canary Key

## Why nobody knows the private key

A secp256k1 public key is a point `P = k·G`. Normally you pick `k` and compute `P`. Here we do the reverse: we derive the point `P` directly from a public phrase with a **hash-to-curve** function, without ever choosing `k`. Finding `k` from `P` is the discrete-log problem. It is infeasible for classical computers and exactly what Shor's algorithm solves on a large quantum computer.

So:
- Everyone can re-run the derivation and get the same `P`, which proves nobody hand-picked it.
- A valid ECDSA signature under `P` can only come from someone who solved discrete log for this curve.
- That signature, checked on-chain by `ecrecover`, is the trigger.

## Real canary parameters (fixed; do not change after deploy)

| Field | Value |
|---|---|
| Standard | RFC 9380, suite `secp256k1_XMD:SHA-256_SSWU_RO_` (random-oracle variant, `hash_to_curve`, not `encode_to_curve`) |
| DST (domain separation tag) | `CANARY-V1-QORECHAIN_XMD:SHA-256_SSWU_RO_` |
| Message | `QoreChain Canary 2026 #1` (UTF-8) |
| Output | Uncompressed point `04‖X‖Y`; EVM address = last 20 bytes of `keccak256(X‖Y)` |

Store the DST and message in the registry (`phrase`, `dst`) and in the README.

## Scripts (`scripts/`)

Library: `@noble/curves` (secp256k1 hash-to-curve) and `viem` (`keccak256`, `publicKeyToAddress`). Check the installed version's API before writing code: v1.x exports `hashToCurve` from `@noble/curves/secp256k1`, and v2.x exposes it on `secp256k1_hasher`. Pin the version in `package.json`.

### `derive-canary.ts`

```text
pnpm canary:derive --msg "QoreChain Canary 2026 #1" --dst "CANARY-V1-QORECHAIN_XMD:SHA-256_SSWU_RO_"
→ prints: point X, Y (hex), uncompressed pubkey, EVM address, qor1 address
→ writes deployments/canary.json { msg, dst, x, y, pubkey, address }
```

### `verify-canary.ts`

1. `--selftest`: run the secp256k1 `hash_to_curve` test vectors from **RFC 9380 Appendix J.8.1** (copy the DST, messages and expected X/Y exactly from the RFC). All must match, or exit non-zero. This proves our library call is the standard construction.
2. Re-derive from the given `--msg` and `--dst` and compare to `deployments/canary.json` and to the address stored on-chain in `CanaryRegistry` (via an `eth_call`).

Run both in CI (`pnpm test:scripts`).

### `gen-test-canary.ts`

Generates a normal random secp256k1 keypair for the **test canary**. Writes the private key to `.env` as `TEST_CANARY_PRIVATE_KEY` (git-ignored) and the address to `deployments/test-canary.json`. Refuses to overwrite an existing key unless `--force` is passed.

### `kill-test-canary.ts` (the demo trigger)

```text
pnpm demo:kill --canary 1 --reporter <reporter 0x address>
```

1. Read `breakDigest(1, reporter)` from the registry (view call). Do not rebuild it off-chain; reading it guarantees the same bytes.
2. Sign the **raw** 32-byte digest with `TEST_CANARY_PRIVATE_KEY` (noble `secp256k1.sign(digest, key)`; take `r`, `s`, and `v = recovery + 27`). No Ethereum message prefix.
3. Submit `reportBreak(1, reporter, v, r, s)` from the `reporter` account (needs a scoped window that includes the registry).
4. Print the tx hash, `deadAt`, and the `CanaryDied` event.

Guard: the script refuses canary id 0 (the real canary). For the video, also add `pnpm demo:try-real` that submits a random signature for canary 0 and shows the `InvalidBreakSignature` revert, to show the real canary cannot be killed.

## Browser re-derivation (web app, P0)

The **Canary** page has a "Verify this canary yourself" panel:
- Shows the message and DST, with copy buttons.
- A "Re-derive in my browser" button runs the same `@noble/curves` call client-side and shows the computed address next to the on-chain address, with a match or mismatch badge.
- Links to RFC 9380 and to `scripts/verify-canary.ts`.

## Tests

- Foundry: deploy the registry with a known test keypair; a valid raw signature over `breakDigest` kills it; wrong reporter, wrong id, wrong chain, a second report, and a zero-address recovery all revert.
- Scripts: the RFC 9380 vectors pass; derive is deterministic (same output on every run); the on-chain address matches.
- A Foundry test asserting the real canary's address in the registry equals the value from `deployments/canary.json` (hard-code the derived address as a test constant once derived).
