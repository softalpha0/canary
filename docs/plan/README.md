# Canary — Build Plan (Post-Quantum dApp)

Canary is a cover pool that pays out the moment anyone proves today's elliptic-curve crypto has been broken.
It is built solo for the QoreChain **Build Before Q-Day** hackathon, category **Post-Quantum dApp**.

- **Deadline:** 2 Dec 2026, 23:59 UTC (building closes; checks run 3–5 Dec, judging 6–15 Dec)
- **Category prizes:** 1st $1,500 · 2nd $750 · 3rd $500 (team size 1–3)
- **Category requirements:** scoped EVM window, `pqcVerify`, two-stage QCAI audit, Foundry or Hardhat tests
- **Plan written:** 21 Nov 2026, from the QoreChain docs, kit READMEs and existing entries as they stood that day

## How to use these files

Give the whole folder to your AI coding agent. Put it in the new repo as `docs/plan/` and tell the agent to start with `AGENT_BRIEF.md`.

| File | What it holds | Read when |
|---|---|---|
| [AGENT_BRIEF.md](AGENT_BRIEF.md) | Rules for the agent: how to work, what never to do, when to stop and ask | First, always |
| [01_PRODUCT_SPEC.md](01_PRODUCT_SPEC.md) | What Canary is, users, user stories, scope (P0/P1/P2), non-goals | Before any code |
| [02_ARCHITECTURE.md](02_ARCHITECTURE.md) | Components, accounts and keys, the signing model, every flow | Before any code |
| [03_SMART_CONTRACTS.md](03_SMART_CONTRACTS.md) | Contract-by-contract spec: storage, functions, events, errors, math, invariants | Building contracts |
| [04_CANARY_KEY.md](04_CANARY_KEY.md) | Hash-to-curve canary derivation, test canary, the kill script | Building scripts |
| [05_QORECHAIN_INTEGRATION.md](05_QORECHAIN_INTEGRATION.md) | Network facts, EVM window, key registration, precompiles, deployment, known unknowns | Any chain work |
| [06_FRONTEND.md](06_FRONTEND.md) | Web app pages, components, wallet wiring, states | Building the app |
| [07_TESTING_AND_AUDIT.md](07_TESTING_AND_AUDIT.md) | Foundry test plan, testnet end-to-end, two-stage QCAI audit | Throughout |
| [08_MILESTONES.md](08_MILESTONES.md) | Day-by-day tasks with acceptance criteria, 21 Nov → 2 Dec | Daily |
| [09_SUBMISSION.md](09_SUBMISSION.md) | Pre-judging checklist, README outline, AI_USAGE, video script, project page | From 29 Nov |
| [10_THREAT_MODEL_SEED.md](10_THREAT_MODEL_SEED.md) | Starting content for `docs/THREAT_MODEL.md` | 30 Nov |

## Kickoff prompt for your agent

Paste this as your first message to the agent, from inside the new, empty repo:

```text
You are building "Canary", a Post-Quantum dApp for the QoreChain Build Before Q-Day hackathon.
The full plan is in docs/plan/. Read docs/plan/AGENT_BRIEF.md first and follow it exactly,
then read 01 to 07 in order. Then start milestone M0 in docs/plan/08_MILESTONES.md.
Work one milestone at a time. At the end of each milestone, show me the acceptance
criteria with evidence (test output, tx hashes, screenshots) before moving on.
Anything marked SPIKE must be proven on testnet before code depends on it.
```

## The three things that decide this project

1. **Day-1 spikes (M0).** Several QoreChain behaviours are documented loosely: how QoreX signs bytes for `pqcVerify`, whether `forge script` deploys cleanly, and how windows behave. M0 proves them on testnet before any product code. Do not skip it.
2. **Every sensitive action is authorised by an ML-DSA-87 signature checked on-chain with `pqcVerify`.** That is the category's core requirement and Canary's whole story: when the canary dies, ECDSA is dead, so Canary never trusts ECDSA for money.
3. **A live, believable demo.** The test canary is killed on camera and payouts flow. Plan the video from day 1.
