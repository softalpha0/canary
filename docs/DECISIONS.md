# Decisions

Changes to, or clarifications of, the plan in `docs/plan/`, with reasons (AGENT_BRIEF §1.3). Items marked **ASK** need the owner's answer.

## D-001 — `msgMode` = `MODE_RAW` (provisional) · 2026-11-22

- **Decision:** deploy both pools with `msgMode = MODE_RAW` (0): `pqcVerify` gets the raw 32-byte action digest.
- **Evidence:** S3 Track B PASS (`docs/SPIKES.md`). A real ML-DSA-87 signature over a raw digest verifies on testnet; tampered inputs fail.
- **Pending:** S3 Track A (QoreX) needs the owner's browser run. If an encoding passes, we switch to `MODE_QOREX` with that encoding before the M2 deploy (it is an immutable constructor arg). If no encoding passes, `MODE_RAW` is final and the app uses the "Sign with the Canary CLI" modal (plan 02 §Track B).

## D-002 — Accounts created with the SDK, not `qorechaind keys add` · 2026-11-22

- The plan's example uses `qorechaind keys add <name> --key-type eth_secp256k1 --coin-type 60`. I generated the four accounts with `@qorechain/sdk` `deriveUnifiedAccount(mnemonic)` instead. That gives the same key type (eth_secp256k1, HD path `m/44'/60'/0'/0/0`), and the plan already names the SDK as the preferred registration route ("SDK (preferred, matches Track B)").
- Why: the mnemonic is the single secret. It derives the EVM key (MetaMask import), the native signer and the canonical ML-DSA-87 key used by both registration and Track B signing. Nothing is spread across a CLI keyring and `.dilithium` files.
- `qorechaind` is not needed for registration or windows (`MsgRegisterPQCKeyV2` and `MsgOpenEVMWindow` are both sent through `EthNativeSigner`). It stays an optional fallback; the testnet binary v3.2.8 is published at `download.qore.host`.
- Not a scope change. Recorded for transparency.

## D-003 — No `dotenv` dependency · 2026-11-22

Scripts load `.env` with Node's built-in `process.loadEnvFile` (Node ≥ 20.12), so no dependency is added outside the plan (AGENT_BRIEF §4).

## D-004 — Gas for PQ-authorised calls is higher than the plan assumed · 2026-11-22 — **ASK (informational)**

- Plan 03 says `pqcVerify` costs ~85–90k per call and an authorised call ~250–350k. Measured: a bare `pqcVerify` `eth_call` estimates at **~312k gas** (S3). With calldata (4,627-byte signature) and `pqcKeyStatus`, an authorised call may need **~400–500k**.
- Impact: about 0.04–0.05 QOR per authorised call at the 0.1 uqor/gas floor. That is still well inside the faucet budget. The app's starting gas limit of 600k (plan 06) may need to go to ~800k; S2 will measure the real in-contract number (`PQProbe.probe`) and I'll set the limits from that.
- No design change proposed. Owner: no action needed unless you object.

## D-005 — Spike contracts live in `contracts/test/spikes/` · 2026-11-22

`Counter` and `PQProbe` are throwaway S2 contracts. Keeping them out of `src/` keeps the M1 coverage target (≥ 90% lines on `src/`) about the real contracts.
