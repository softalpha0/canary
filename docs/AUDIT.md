# QCAI Audit

Canary runs QoreChain's AI audit in two stages, as the Post-Quantum dApp category requires (plan 07 §4). The owner runs each stage, since it needs their dashboard sign-in. The agent prepares the source and records every finding here.

- **Source audited:** [`contracts/flattened/Canary.flat.sol`](../contracts/flattened/Canary.flat.sol). It contains `CoverPool`, `CanaryRegistry`, `PQAuth`, the precompile interfaces and OpenZeppelin v5.4.0 `ReentrancyGuard`/`Math`, flattened into one file. `forge build --contracts flattened/Canary.flat.sol` compiles it.
- **Setting:** Blockchain **Ethereum (EVM/Solidity)**, the same for both stages (the FAQ requires this).
- **Quantum readiness:** the tool shows "Not scored" for EVM settings. That is expected. Canary's post-quantum protection is ML-DSA-87 authorisation through the `pqcVerify` precompile; see `PQAuth.sol`.

## How to run a stage (owner)

1. Go to https://dashboard.qorechain.io/audit (sidebar **Build → AI Audit**).
2. Blockchain: **Ethereum (EVM/Solidity)**. Name: `Canary — Stage 1` (or `Stage 2`).
3. Paste the whole of `contracts/flattened/Canary.flat.sol`. Click **Run Security Audit** and confirm.
4. **Export PDF** and save it as `docs/audit/2026-MM-DD-stage1.pdf` (or `stage2`). Commit it, or send it to the agent.

The first audit each UTC day is free, so run the two stages on different days.

## Stage 1 — first complete contracts

- Date: _pending (owner)_
- Commit audited: _pending_
- PDF: _pending_ (`docs/audit/…-stage1.pdf`)

| # | Finding | Severity | Decision (fixed / false positive / accepted risk) | Commit or test |
|---|---|---|---|---|
| | _to be filled from the Stage 1 report_ | | | |

## Stage 2 — after fixes

- Date: _pending (M4)_
- PDF: _pending_

| # | Finding | Severity | Decision | Commit or test |
|---|---|---|---|---|
| | | | | |
