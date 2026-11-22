# 08 — Milestones (solo, 21 Nov → 2 Dec 2026)

`[OWNER]` = only the human can do it (sign-ins, faucet, QoreX, audits, publishing). Everything else is the agent's. Each milestone ends with the report format from `AGENT_BRIEF.md`.

**Every day [OWNER]:** claim the faucet into `deployer` (100 QOR), and push at least one commit. Optional: post a progress update on X (helps People's Choice and shows the jury how the project came together).

---

## M0 — Setup and spikes · Fri 21 – Sat 22 Nov

**Owner first:**
- [ ] [OWNER] Create the public GitHub repo `canary` (Apache-2.0) and the project on build.qorechain.io under **Post-Quantum dApp** ("Create your project" on the Start page). Tick the AI-native option.
- [ ] [OWNER] Install `qorechaind` (testnet build), the QoreX desktop extension and MetaMask. Claim the faucet.

**Agent:**
- [ ] Scaffold the repo per `AGENT_BRIEF.md` §5: pnpm workspace, Foundry project, `scripts/` (tsx), `.gitignore`, `.env.example`, LICENSE, README stub, `docs/SPIKES.md`, `docs/DECISIONS.md`, `docs/DEPLOYMENTS.md`. Optional: run `npx create-qorechain-dapp tmp --template foundry --yes --no-install` in a scratch folder and copy its EVM-window helper and network config if useful; don't commit the scratch folder.
- [ ] Create 4 `eth_secp256k1` accounts (`deployer`, `lp1`, `buyer1`, `reporter`); secrets in `.env` only. Fund them from `deployer`.
- [ ] **S1** Register ML-DSA-87 keys with proof for all 4. Prove derived pubkey == on-chain pubkey.
- [ ] **S2** Deploy a throwaway `Counter` + a `PQProbe` contract (calls both precompiles) with an unscoped window. Then open a scoped window and prove allowed vs refused calls.
- [ ] **S3** Track B: `pqcVerify` true via `eth_call` on a real signature. Track A: try QoreX `signArbitrary` encodings. Record results either way.
- [ ] **S4** MetaMask tx on chain 9800 inside a scoped window, receipt parsed by viem.
- [ ] **S5** `eth_getLogs` max range.
- [ ] Write `scripts/window.ts` (status, open-scoped, open-deploy, close).

**Acceptance:** S1, S2, S4 pass and S3 Track B passes, each with tx hashes in `SPIKES.md`. `msgMode` is decided and written in `DECISIONS.md`. If any of S1, S2, S3-B or S4 fails → stop and ask the owner.

## M1 — Contracts · Sun 23 – Mon 24 Nov

- [ ] `IQorePQC.sol`, `PQAuth.sol` + harness and tests.
- [ ] `CanaryRegistry.sol` + tests.
- [ ] `CoverPool.sol`: deposit, buy, expire, withdraw (request, cancel, execute), death handling, payout, bounty, settlement, admin + tests.
- [ ] Invariant suite.
- [ ] `actionDigest` test vector exported; `scripts/lib/digest.ts` matches it.

**Acceptance:** `forge test` all green; coverage ≥ 90% lines on `src/`; invariants at 256 runs × depth 50 pass; gas snapshot committed; `forge fmt --check` clean.

## M2 — Canary scripts, testnet deploy, audit stage 1 · Tue 25 Nov

- [ ] `derive-canary.ts`, `verify-canary.ts` (RFC 9380 vectors), `gen-test-canary.ts`, `kill-test-canary.ts`, `try-real` negative script, `pq-sign.ts`, `deploy.ts` (or `Deploy.s.sol`), `verify-bytecode.ts`.
- [ ] Deploy registry + 2 pools to testnet. Write `deployments/testnet.json` and `DEPLOYMENTS.md`.
- [ ] Seed the test pool: `lp1` deposits 20 QOR; seed the real pool: 10 QOR.
- [ ] Flatten contracts for the audit; draft `docs/AUDIT.md`.
- [ ] [OWNER] Run **QCAI Stage 1**; save the PDF to `docs/audit/`.

**Acceptance:** contracts live; `verify-canary.ts` passes against the chain; `verify-bytecode.ts` matches; one real PQ-signed tx (for example `requestWithdraw`) succeeds on testnet from a scoped window; Stage 1 PDF committed.

## M3 — Web app · Wed 26 – Thu 27 Nov

- [ ] Scaffold app, config from `deployments/testnet.json`, chain definition, top bar, routing.
- [ ] `/setup` checklist (all five checks live).
- [ ] `/` and `/canary/:id` with in-browser re-derivation.
- [ ] `/pool/:id` LP panel and cover panel.
- [ ] `PQAuthorizeButton` (Track A if enabled, Track B modal always available), with the `pqcVerify` pre-check.
- [ ] `/policies` with claim and expire; `/admin`.
- [ ] Dead-canary banner and 5-second polling. Error mapping.

**Acceptance:** from the browser only (plus the Track B command if needed), a fresh account can complete setup, deposit, buy cover, request and execute a withdrawal. Screenshots of each in `docs/screenshots/`. Vitest green.

## M4 — Audit fixes, stage 2, full E2E · Fri 28 Nov

- [ ] Resolve every Stage 1 finding (fix + regression test, or documented false positive). Update `AUDIT.md`.
- [ ] Redeploy if contracts changed; update `deployments/testnet.json`, re-seed pools.
- [ ] [OWNER] Run **QCAI Stage 2**; save the PDF.
- [ ] Run `scripts/e2e.ts` end to end; record all hashes.

**Acceptance:** `AUDIT.md` maps every Stage 1 finding to an outcome; Stage 2 PDF committed; E2E run fully green with hashes; the claim replay reverts; the real canary can't be killed.

## M5 — Polish and P1 · Sat 29 Nov

- [ ] Full rehearsal of the demo story in the browser (kill → banner within 5 s → claim → withdraw).
- [ ] P1, only if M0–M4 are fully done: QoreSeal sealed policy notes (`noteHash`), `/activity` feed, Playwright happy path.
- [ ] UI polish pass: empty states, loading, copy buttons, explorer links, responsive at 768 px.

**Acceptance:** rehearsal recorded as a rough screen capture; no console errors; Lighthouse accessibility ≥ 90 on `/` and `/pool/1`.

## M6 — Docs and submission assets · Sun 30 Nov

- [ ] `docs/THREAT_MODEL.md` (from `10_THREAT_MODEL_SEED.md`).
- [ ] `README.md` per `09_SUBMISSION.md` outline, with every requirement linked to code and txs.
- [ ] `AI_USAGE.md`.
- [ ] Cover image (16:9, ≥ 1200×675) — the agent can produce an SVG and export a PNG; the owner approves it.
- [ ] Video script and shot list (in `09_SUBMISSION.md`) adapted to the final UI.

**Acceptance:** a stranger following the README can re-derive the canary and run the tests; every checklist item in `09_SUBMISSION.md` up to "video" is ticked.

## M7 — Video, outside tester, final deploy · Mon 1 Dec

- [ ] Fresh redeploy of the **test** registry and pool for the recording (the old test canary is dead). Keep the old addresses in `DEPLOYMENTS.md` as evidence.
- [ ] [OWNER] Record the video (≤ 3:00) and upload; add the link to the README and the project page.
- [ ] [OWNER] One outside tester follows `/setup` and buys cover; fix anything they trip on.
- [ ] [OWNER] Fill in the project page: description, cover image, video, repo, every `qor1…` address, category Post-Quantum dApp, kits, "How it's made" (with the audit line).

**Acceptance:** project page shows kits Verified (SDK, pqc, qoresign) and network features Verified (window incl. scoped, hybrid ML-DSA-87 txs, PQC key registration); video link live.

## M8 — Buffer and submit · Tue 2 Dec (deadline 23:59 UTC)

- [ ] Final run of `09_SUBMISSION.md` checklist. Press "Check again" on the project page.
- [ ] Freeze: no contract changes on this day. Only docs and small UI fixes.

---

## If you fall behind — cut in this order

1. P1 items (QoreSeal notes, activity feed, Playwright).
2. Track A (QoreX signing): ship Track B only, explained in the README.
3. `/admin` page (keep the admin functions and their tests; call them from a script).
4. Real-pool seeding (the test pool carries the demo).

Never cut: PQ-authorised withdraw and claim, scoped windows, the two audit stages, Foundry tests, the canary derivation, the E2E run, the video.
