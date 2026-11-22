# Decisions

Changes to, or clarifications of, the plan in `docs/plan/`, with reasons (AGENT_BRIEF §1.3). Items marked **ASK** need the owner's answer.

## D-001 — `msgMode` = `MODE_RAW` (final) · 2026-11-22

- **Decision:** deploy both pools with `msgMode = MODE_RAW` (0): `pqcVerify` gets the raw 32-byte action digest, signed with Track B (`scripts/pq-sign.ts`, key from the owner's mnemonic).
- **Evidence:** S3 Track B PASS, by `eth_call` and in a real tx (`PQProbe.probe`, `0x45cbdf4f…85e6`).
- S3 Track A (QoreX) was not settled; the owner skipped it (SPIKES.md S3). Per plan 02, the app shows the "Sign with the Canary CLI" step. `MODE_QOREX` stays in `PQAuth` for completeness, but no pool deploys with it unless Track A is proven later.

## D-002 — Accounts created with the SDK, not `qorechaind keys add` · 2026-11-22

- The plan's example uses `qorechaind keys add <name> --key-type eth_secp256k1 --coin-type 60`. I generated the four accounts with `@qorechain/sdk` `deriveUnifiedAccount(mnemonic)` instead. That gives the same key type (eth_secp256k1, HD path `m/44'/60'/0'/0/0`), and the plan already names the SDK as the preferred registration route ("SDK (preferred, matches Track B)").
- Why: the mnemonic is the single secret. It derives the EVM key (MetaMask import), the native signer and the canonical ML-DSA-87 key used by both registration and Track B signing. Nothing is spread across a CLI keyring and `.dilithium` files.
- `qorechaind` is not needed for registration or windows (`MsgRegisterPQCKeyV2` and `MsgOpenEVMWindow` are both sent through `EthNativeSigner`). It stays an optional fallback; the testnet binary v3.2.8 is published at `download.qore.host`.
- Not a scope change. Recorded for transparency.

## D-003 — No `dotenv` dependency · 2026-11-22

Scripts load `.env` with Node's built-in `process.loadEnvFile` (Node ≥ 20.12), so no dependency is added outside the plan (AGENT_BRIEF §4).

## D-004 — Gas for PQ-authorised calls; set limits from estimates · 2026-11-22 (updated after S2)

- Plan 03 estimated ~250–350k gas per authorised call. **Measured (S2):** a PQ-authorised call with a 4,627-byte signature (`PQProbe.probe`) needs **~235k gas**, and in-contract `pqcKeyStatus` + `pqcVerify` cost ~154k. Within the plan's range.
- **New fact:** the chain charges `gasUsed ≥ 50% of the gas limit` (every S2 receipt: exactly 0.500 × limit). A flat 600k limit (plan 06 §5) would cost 300k gas, more than needed. Decision: scripts and the app set `gas = eth_estimateGas × 1.25`, with a fixed fallback only if estimation fails. Plan 05 warns that estimation can fail; on this RPC it worked for every call in S2.
- Cost: about 0.03–0.04 QOR per authorised call. No design change.

## D-007 — Primary deploy route: viem · 2026-11-22

Both routes deployed successfully in S2. But `forge script` executes the script locally before broadcasting, and local EVMs lack the `0x…0a02` precompile that the CoverPool constructor calls, so it would revert there. Canary deploys with `scripts/deploy.ts` (viem + Foundry artifacts + runtime-code check), as plan 05 §Deploying allows. `forge script` stays available through `scripts/forge-script.ts` for contracts that don't touch the precompiles.

## D-005 — Spike contracts live in `contracts/test/spikes/` · 2026-11-22

`Counter` and `PQProbe` are throwaway S2 contracts. Keeping them out of `src/` keeps the M1 coverage target (≥ 90% lines on `src/`) about the real contracts.

## D-006 — One-time author rewrite of the first 3 commits (owner-approved) · 2026-11-22

- AGENT_BRIEF §1.5 says never rewrite pushed history. The owner explicitly asked for this one exception: the first three commits (`f439e22`, `1248fc0`, `e6f8681`) were authored as "Claude" only, and the owner wants to be the author with Claude as co-author.
- Done with `git filter-branch --env-filter` changing only author/committer name and email. **Commit dates, messages, trees and order are unchanged**, so the hackathon's "commits made during the event" check is unaffected. Follow-up the same day: the owner corrected the author email to the one on their GitHub account, so the commits were rewritten once more the same way (email only). Final hashes: `c750c76`, `435b8c9`, `a731739`, `b89aee9`.
- From now on every commit is authored by the owner (`softalpha0`) with a `Co-Authored-By: Claude` trailer. No further history rewrites.

## D-008 — S4 MetaMask run waived by owner; M0 closed · 2026-11-22

- M0 acceptance requires S4 ("MetaMask tx … inside a scoped window"). The owner chose to skip the MetaMask run and move to M1.
- Recorded instead: the same EIP-1559 tx sent from deployer's key with viem inside the scoped window, receipt parsed by viem (SPIKES.md S4, tx `0xa2db35a1…e5d4`). MetaMask did connect to chain 9800.
- Residual risk: MetaMask signing and sending on 9800 is untested until M3. If it fails there, the app falls back to showing a script command (the same pattern as Track B).

## D-009 — Small additions to the contract spec · 2026-11-22 (M1)

None changes behaviour the plan defines. They make failures explicit:

- **Implicit nonce.** Authorised functions take no `nonce` argument (as specified); the pool signs over `nonces[owner]`. A replayed signature therefore fails as `PQBadSignature` (the nonce moved on), not `BadNonce`. `BadNonce(expected)` is exercised in the explicit-nonce `PQAuthHarness` (`PQAuth.t.sol`). Replay is covered by unit tests and by invariant 5 (`invariant_noReplay`, 256 × 50).
- **Extra errors:** `ZeroAmount` (zero cover/shares, cover > uint128, deposit that mints 0 shares), `ZeroAddress` (zero registry/admin/recipient), `UnknownId` (out-of-range request/policy id), `BadConfig` (constructor bounds: minDuration > 0, min ≤ max, bps ≤ 10,000, rate ≤ maxRate, mode ≤ 1, minDeposit > 0, canaryId < registry.count()). `PQAuth` adds `PQBadPubkeyLength` (pubkey ≠ 2,592 bytes; the plan asks for the check but names no error) and `PQBadMode`. `CanaryRegistry` adds `InvalidCanary(index)` and `NoCanaries` for constructor validation.
- **Extra views:** `CanaryRegistry.getCanary(id)` (full struct incl. strings, for the app), `CoverPool.totalAssets()` / `isDead()`, and public action constants (`CLAIM_PAYOUT()` etc.) so scripts read them from the contract.
- **Settled pools:** `expire()` reverts `AlreadySettled` after settlement (activeCover is already 0; subtracting again would underflow).
- **Not yet done:** plan 07's "real canary address == derived constant" test needs the M2 derivation script (`derive-canary.ts`); it lands in M2.
