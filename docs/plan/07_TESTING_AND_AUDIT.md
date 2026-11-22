# 07 — Testing and the QCAI Audit

## 1. Foundry unit tests (`contracts/test/`)

### Precompile mocks

Local EVMs don't have QoreChain's precompiles, so tests install mocks **at the real addresses** with `vm.etch`:

- `MockPQCKeyStatus` etched at `0x…0a02`, with a setter `setKey(address, bool registered, uint8 algo, bytes pubkey, bool proven)`. Storage lives at the etched address, so call the setter on that address.
- `MockPQCVerify` etched at `0x…0a01`. A deterministic fake scheme: a signature is valid if it is 4,627 bytes long and its first 32 bytes equal `keccak256(abi.encodePacked(pubkey, message))`. A test helper `fakeSign(pubkey, message)` builds one.
- **Absent precompile:** `vm.etch(addr, "")` makes calls return success with empty data, which is what an inactive precompile does on-chain. Every authorised function must revert `PQPrecompileUnavailable`.

The mocks only stand in for the precompiles. Real ML-DSA is tested on testnet in section 3.

### Test files and cases

**`CanaryRegistry.t.sol`**
- Constructor stores canaries; rejects a zero address.
- `reportBreak` with a valid raw signature over `breakDigest` marks dead, sets `deadAt` and `reporter`, emits `CanaryDied`.
- Reverts: wrong signer; signature for another reporter; another canary id; a second report (`AlreadyDead`); unknown id; zero reporter; malformed `v`.
- `breakDigest` changes when the chain ID changes (`vm.chainId`).
- The real canary's on-chain address equals the derived constant from `deployments/canary.json`.

**`PQAuth.t.sol`** (through a small harness contract)
- Valid signature passes; the nonce is consumed and the next use reverts `BadNonce`.
- Each field changes the digest: owner, action, every param, contract address, chain ID, nonce, deadline.
- Expired deadline → `PQExpired`. Key not registered, not proven, wrong algorithm, wrong pubkey length → the matching error.
- Wrong signature length → `PQBadSignature`. Absent precompiles → `PQPrecompileUnavailable`.
- Exported **test vector**: for fixed inputs, log the digest bytes. The app's and scripts' digest builders are tested against it.

**`CoverPool.t.sol`**
- Deposit: shares minted; first depositor protected by the virtual offset (the inflation-attack test: an attacker donates QOR, and the victim's shares stay fair); refused for receivers without a proven key; refused after death; below the minimum refused.
- Premium: `quotePremium` matches the formula, including rounding up; wrong `msg.value` reverts with the expected amount.
- Capacity: cover up to free capital succeeds; one wei more reverts `NoCapacity`.
- Withdraw: request locks shares; execute before cooldown reverts; after cooldown it pays the right assets to the chosen recipient; cancel unlocks; cannot withdraw locked or another owner's shares; execution limited by free capital.
- Front-running: request a withdrawal, the canary dies during cooldown, execute → the LP gets only their share of `netAssets()` (after liabilities), never cover-backing funds.
- Expiry: `expire` releases capacity; refused before expiry; after death refused for policies with `expiry > deadAt`.
- Payout: after death an eligible policy pays exactly `coverAmount` to the signed recipient; double claim reverts; policies bought after death are impossible; claim after the window reverts; a claim signed for recipient A cannot be redirected to B.
- Bounty: paid once, to the registry's reporter, capped and limited to free capital; payouts remain fully funded afterwards.
- Settlement: before the window ends it reverts; after, `activeCover` becomes 0 and LPs can withdraw everything.
- Admin: rate and pause need the admin's PQ signature; a non-admin signature fails; the rate above `maxRateBps` reverts; pause blocks `buyCover` only.
- Reentrancy: a malicious recipient contract re-entering `executeWithdraw` or `claimPayout` fails.

**`CoverPool.invariant.t.sol`** — a handler drives random deposits, purchases, requests, executions, expiries, warps, a death, claims and settlement across several actors. Assert the 7 invariants from `03_SMART_CONTRACTS.md` after every step. Use at least 256 runs and depth 50 in CI.

### Commands and bars

- `forge test -vvv` passes. `forge coverage` shows at least 90% line coverage on `src/`. `forge snapshot` is committed (`.gas-snapshot`).
- `forge fmt --check` is clean.

## 2. Script and app tests

- `pnpm test:scripts`: the RFC 9380 vectors; derivation determinism; JS digest equals the Foundry test vector; Track B `pq:sign` output verifies locally with `@qorechain/pqc`.
- `pnpm --filter app test`: Vitest units listed in `06_FRONTEND.md`.

## 3. Testnet end-to-end (`scripts/e2e.ts`)

Runs the full story on the **test pool** with real ML-DSA signatures (Track B), and writes every tx hash to `docs/DEPLOYMENTS.md` under "E2E run <date>":

1. `lp1` deposits 20 QOR.
2. `buyer1` buys 5 QOR of cover for 10 minutes.
3. `lp1` requests a withdrawal of half their shares (PQ-signed).
4. `demo:kill` kills the test canary (the `reporter` submits).
5. `claimBounty()` pays the reporter.
6. `buyer1` claims the payout to a fresh recipient (PQ-signed). Check the recipient's balance went up by exactly 5 QOR.
7. Replay the same claim signature → it must revert.
8. After the cooldown, `lp1` executes the withdrawal (PQ-signed).
9. After the 1-hour claim window, `finalizeAfterClaimWindow()`.
10. Negative check: `demo:try-real` cannot kill canary 0.

All txs are sent from accounts with **scoped** windows (targets = the registry and the pools). That also produces the on-chain evidence for the "EVM window (incl. scoped)" network feature.

Redeploy the test pool and registry for the video if needed (a dead canary stays dead). Keep the first E2E run's hashes as evidence.

## 4. Two-stage QCAI audit

The tool is at `https://dashboard.qorechain.io/audit` (sidebar **Build → AI Audit**). It needs the owner's sign-in, so **the owner runs it**; the agent prepares everything.

Agent prepares:
- `contracts/flattened/Canary.flat.sol`: both contracts flattened into one file (`forge flatten`), with duplicate SPDX and pragma lines cleaned up, and `forge build` still passing on it.
- `docs/AUDIT.md` with a section per stage.

Owner runs each stage:
1. Open **AI Audit**. Blockchain: **Ethereum (EVM/Solidity)**, the same setting for both stages (the FAQ requires this). Name: `Canary — Stage 1` (or `Stage 2`). Paste the flattened source. **Run Security Audit**, then confirm.
2. **Export PDF.** Save it as `docs/audit/2026-MM-DD-stage1.pdf` (or `stage2`). The first audit each UTC day is free; others cost test QOR, so run the two stages on different days.

Stages:
- **Stage 1 (M2, 25 Nov):** audit the first complete contracts.
- **Fix:** for every finding, do one of: fix it and add a regression test; or document it as a false positive with reasoning. Record each in `docs/AUDIT.md` as a table: finding, severity, decision (fixed, false positive, accepted risk), commit hash or test name.
- **Stage 2 (M4, 28 Nov or later):** audit the fixed code. Record the result the same way.
- Add one line to the README and to the project page's "How it's made" pointing to `docs/AUDIT.md`. Note: quantum readiness shows "Not scored" for EVM settings. That is expected; say so in `AUDIT.md`.
