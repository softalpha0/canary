# 09 — Submission Kit

## Pre-judging checklist (checked 3–5 Dec)

- [ ] Project on build.qorechain.io, category **Post-Quantum dApp**, team size 1
- [ ] Owner fully registered: GitHub, X, QoreX testnet address
- [ ] Public GitHub repo with LICENSE (Apache-2.0)
- [ ] Commits made during the hackathon, spread over the days
- [ ] README (outline below)
- [ ] Cover image, 16:9, at least 1200×675
- [ ] Demo video, 3:00 or less, link on the project page and in the README
- [ ] At least one `qor1…` testnet address on the project page (list all four demo accounts)
- [ ] Kits detected (Verified): `@qorechain/sdk`, `@qorechain/pqc`, `@qorechain/qoresign` (+ `@qorechain/qorex-rainbowkit`, `@qorechain/qoreseal` if used)
- [ ] Network features Verified: EVM window (incl. scoped), hybrid ML-DSA-87 transactions, PQC key registration with proof of possession
- [ ] Declared and easy to find by hand: Solidity PQC signature check, Solidity PQC key status
- [ ] Category requirements, each linked from the README:
  - [ ] Scoped EVM window — `scripts/window.ts` + tx hashes of scoped windows
  - [ ] `pqcVerify` — `contracts/src/lib/PQAuth.sol` + PQ-signed claim and withdraw tx hashes
  - [ ] Two-stage QCAI audit — `docs/audit/*.pdf` + `docs/AUDIT.md`
  - [ ] Foundry tests — `contracts/test/` + how to run, coverage number
- [ ] `docs/THREAT_MODEL.md`
- [ ] `AI_USAGE.md` and the AI-native option ticked
- [ ] Every open-source library, kit and template credited in the README

## README outline

```markdown
# Canary — a Q-Day tripwire with post-quantum payouts

> One line pitch. Badges: testnet, licence, tests.

[cover image]  [▶ 3-min demo video]  [Live app]  [Project page]

## What it does            (4 sentences + the 3-step diagram)
## Why the canary can't be faked
   (hash-to-curve in plain words; phrase + DST; "verify it yourself" command)
## Post-quantum by design
   (table: action → who signs → checked by → code link)
## Category requirements   (table: requirement → how → code link → tx evidence)
## Architecture            (mermaid from 02_ARCHITECTURE.md)
## Try it                  (testnet app link; setup in 5 steps; window command)
## Run it locally          (prereqs, pnpm install, forge test, scripts)
## Deployments             (addresses table → docs/DEPLOYMENTS.md)
## Security                (threat model link, audit summary + link, known limits)
## How it was built        (stack; AI_USAGE.md link; timeline)
## Credits                 (every kit, library, template, RFC 9380)
## Licence
```

Rules for the README: claims link to evidence (code line or tx hash); no claim the demo didn't show; "Testnet demonstration, not insurance" near the top.

## AI_USAGE.md template

```markdown
# AI usage

Canary was built by one developer working with an AI coding agent.

## Tools
- <agent / model names and versions>

## What the AI did
- Drafted contracts, tests, scripts and UI from a written plan (docs/plan/)
- Ran spikes against testnet and recorded results (docs/SPIKES.md)
- Prepared the flattened source for the QCAI audits and the fix log

## What the human did
- Product design, all decisions in docs/DECISIONS.md
- Reviewed every milestone, ran the QCAI audits, recorded the video
- Key management, sign-ins and the project page

## Checks on AI output
- Every contract function has tests; invariants fuzzed
- Every QoreChain API call was proven on testnet before use
- <anything else you actually did>
```

Fill it with what really happened. The jury checks it for the Best AI-Native Build award.

## Video script (target 2:45)

| Time | Show | Say (short) |
|---|---|---|
| 0:00–0:15 | Home page, real canary pulsing ALIVE | "Bitcoin and Ethereum keys break on Q-Day. Nobody knows when. Canary is the tripwire, and the cover." |
| 0:15–0:45 | `/canary/0`, press "Re-derive in my browser", match badge | "This key came from hashing a phrase onto the curve. Nobody knows its private key. Re-derive it yourself. Only a quantum computer could sign for it." |
| 0:45–1:10 | `/pool/1`: LP deposit, then buy cover, premium quote | "LPs earn premiums. Buyers get cover. Every account here has a registered ML-DSA-87 key." |
| 1:10–1:30 | `/setup` window chip, scoped targets | "Every transaction runs in a scoped EVM window: only Canary's contracts are allowed." |
| 1:30–1:55 | Terminal: `pnpm demo:kill` on the test canary; browser turns red within 5 s | "This is the test canary. We hold its key, so we can kill it on camera. Watch the app." |
| 1:55–2:25 | `/policies` → Claim → QoreX ML-DSA signature → paid; explorer tx | "ECDSA is now broken, so Canary doesn't trust it. The claim needs my post-quantum signature, checked on-chain by pqcVerify." |
| 2:25–2:40 | Terminal: `demo:try-real` revert; replay of the claim reverts | "The real canary can't be faked, and signatures can't be replayed." |
| 2:40–2:50 | README requirements table, audit PDFs, tests passing | "Scoped windows, pqcVerify, a two-stage QCAI audit, Foundry tests. Canary." |

Record at 1920×1080, browser zoom 110%, hide bookmarks and other extensions, no real personal data on screen.

## Project page text (draft)

- **Name:** Canary
- **Tagline (one line):** A Q-Day tripwire that pays out in post-quantum signatures.
- **Description:** Canary derives a secp256k1 key whose private key nobody knows. A valid signature from it is public proof that elliptic-curve crypto is broken. LPs underwrite cover in QOR; when the canary dies, every active policy pays out. Because ECDSA can't be trusted after that moment, every withdrawal, claim and admin change requires an ML-DSA-87 signature checked on-chain with pqcVerify, and every transaction runs inside a scoped EVM window.
- **How it's made:** Solidity 0.8.24 + Foundry; PQAuth library over pqcVerify and pqcKeyStatus; RFC 9380 hash-to-curve; React + viem; QoreX for ML-DSA signing. Two-stage QCAI audit: see docs/AUDIT.md.

## Cover image brief

1200×675 or larger, 16:9. Dark background; a stylised yellow canary on a lattice or circuit perch; the title "Canary" and the line "If ECDSA dies, you'll know — and get paid." No third-party logos.
