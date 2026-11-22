# Agent Brief — read this first

You are the engineer building Canary. A human (the project owner) reviews your work at the end of each milestone. These rules override any default habit.

## 1. Ground rules

1. **Never invent a QoreChain API.** QoreChain is new and changes often. Before calling any QoreChain package, precompile, CLI command or REST route, find it in the package source, its README, or docs.qorechain.io. If you can't find it, mark it `UNVERIFIED` in code comments and in `docs/SPIKES.md`, and prove it on testnet before relying on it.
2. **Spikes before product code.** Anything tagged `SPIKE` in these plans is an open question. Settle it with a minimal script run against testnet, record the exact command, output and tx hash in `docs/SPIKES.md`, then build on it.
3. **Follow the plan's decisions.** If you believe a decision is wrong, write the reason and your alternative in `docs/DECISIONS.md` and ask the owner. Do not silently diverge.
4. **Scope discipline.** Build P0 completely before touching P1. P2 only if the owner says so. Scope is defined in `01_PRODUCT_SPEC.md`.
5. **Small, real commits.** Commit after each working step with a clear message. The hackathon checks that commits were made during the event (4 Nov–2 Dec 2026). Never squash history, never rewrite history that has been pushed.
6. **Tests are not optional.** Every contract function has unit tests before it is wired into the app. `forge test` must pass before every commit that touches `contracts/`.

## 2. Secrets — hard rules

- Never commit private keys, mnemonics, ML-DSA secret keys, QRC1 recovery codes or `.env` files. `.gitignore` must contain `.env`, `*.dilithium`, `keys/`, `secrets/` before the first commit.
- Keep secrets only in `.env` (git-ignored). Ship a `.env.example` with every variable name and a placeholder value.
- Never print a secret to the console, a log file, a test snapshot or a screenshot.
- The browser app never asks for a mnemonic or private key. ML-DSA signatures in the browser come only from the QoreX extension. Script signing (Track B, see `02_ARCHITECTURE.md`) runs in Node from `.env`, for demo accounts only.
- Testnet only. No mainnet deployments, no real funds.

## 3. Definition of done (any task)

A task is done when all of these are true:

- The code builds with no warnings you introduced.
- Tests covering the change pass, and you show the output.
- Anything on-chain is proven by a testnet tx hash recorded in `docs/DEPLOYMENTS.md` or `docs/SPIKES.md`.
- Docs touched by the change are updated in the same commit.
- The milestone's acceptance criteria in `08_MILESTONES.md` are ticked with evidence.

## 4. Stop and ask the owner when

- A spike fails and the fallback in the plan also fails.
- You would need more than 200 test QOR, or a second faucet account (multiple accounts per person break the hackathon rules).
- A requirement in these plans contradicts what the chain actually does.
- You want to add a dependency not named in these plans (except dev tooling such as linters).
- Anything would publish, post or send something outside this repo and testnet (GitHub repo settings, the hackathon project page, social posts). The owner does those.

## 5. Repo layout to create

```text
canary/
├─ contracts/                 Foundry project (Solidity 0.8.24)
│  ├─ src/
│  │  ├─ CanaryRegistry.sol
│  │  ├─ CoverPool.sol
│  │  ├─ lib/PQAuth.sol
│  │  └─ interfaces/IQorePQC.sol
│  ├─ test/                   unit + invariant tests, mocks for precompiles
│  ├─ script/                 Deploy.s.sol (or a viem/ethers deploy fallback in /scripts)
│  ├─ flattened/              flattened sources pasted into the QCAI audit
│  └─ foundry.toml
├─ scripts/                   TypeScript (Node 20+, tsx): canary derivation, signing, demo, deploy helpers
├─ app/                       Vite + React + TypeScript web app
├─ docs/
│  ├─ plan/                   these files
│  ├─ SPIKES.md               every spike: question, command, output, tx hash, conclusion
│  ├─ DECISIONS.md            any change to the plan, with reason
│  ├─ DEPLOYMENTS.md          addresses, tx hashes, block numbers, dates
│  ├─ THREAT_MODEL.md
│  ├─ AUDIT.md                QCAI findings → what was done
│  └─ audit/                  the two dated QCAI PDF exports
├─ README.md
├─ AI_USAGE.md
├─ LICENSE                    Apache-2.0
├─ .env.example
└─ package.json               pnpm workspace root
```

Use **pnpm** workspaces (`app`, `scripts`). Node 20 LTS or newer.

## 6. Coding standards

- **Solidity:** 0.8.24, `evm_version = "paris"`, optimizer on, 200 runs. Custom errors, not revert strings. Checks-effects-interactions, plus `nonReentrant` on every function that sends value. No `tx.origin`. No upgradeability. NatSpec on every external function.
- **Precompile addresses** in lowercase hex: `0x0000000000000000000000000000000000000a01` and `...0a02`. The compiler rejects mixed-case literals that fail the checksum.
- **TypeScript:** strict mode, viem for EVM reads and writes, no `any` in app code. One `config.ts` per package holds chain IDs, RPC URLs and addresses, read from env, so nothing is hard-coded twice.
- **Errors shown to users** must say what to do next (for example "Your EVM window is closed. Open a scoped window, then retry.").

## 7. Reporting format at the end of each milestone

```text
Milestone Mx — <name>: DONE / BLOCKED
Acceptance criteria:
  [x] criterion — evidence (test output line, tx hash, screenshot path)
  [ ] criterion — why not, and what is needed
Spikes settled: ...
Decisions changed: ... (link DECISIONS.md)
Next: Mx+1, first task
```
