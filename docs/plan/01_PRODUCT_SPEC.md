# 01 — Product Spec

## One line

**Canary pays out the moment anyone proves the crypto behind Bitcoin and Ethereum keys has been broken, and only post-quantum signatures can move its money.**

## The problem

- Wallets on Bitcoin, Ethereum and most chains are secured by ECDSA on the secp256k1 curve. A large enough quantum computer running Shor's algorithm breaks it. That day is called **Q-Day**.
- Nobody knows when Q-Day arrives. Holders have no way to hedge the risk, and no neutral, on-chain signal says "it has happened".
- Any protection that itself relies on ECDSA fails on exactly the day it is needed.

## The idea

1. **The canary.** A secp256k1 public key derived by hashing a fixed phrase onto the curve (RFC 9380 hash-to-curve). Nobody knows its private key, and anyone can re-run the derivation to check. Producing a valid signature for it requires solving the discrete-log problem, which is what a quantum computer would do. **A signature from the canary key is public, verifiable proof that ECDSA is broken.**
2. **The cover pool.** Liquidity providers (LPs) deposit QOR and earn premiums. Cover buyers pay a premium for a fixed amount of cover for a fixed period.
3. **The trigger.** The first valid canary signature submitted on-chain marks the canary dead. New cover stops, and every policy active at that moment can claim its full cover amount.
4. **Post-quantum control.** Every action that moves money out of Canary (LP withdrawals, payout claims, admin changes) requires an ML-DSA-87 signature from the owner's registered post-quantum key, checked on-chain by QoreChain's `pqcVerify` precompile. After Q-Day an attacker holding a broken classical key still cannot take anything.

This is **parametric cover**: payouts depend only on the trigger, not on proving a personal loss.

## Users

| User | Wants | Main actions |
|---|---|---|
| **Cover buyer** | A payout if Q-Day happens, to fund moving assets | Buy cover, view policies, claim payout |
| **Liquidity provider (LP)** | Premium income for underwriting a low-probability event | Deposit, request withdrawal, withdraw |
| **Canary reporter** | A bounty for proving the break | Submit the canary signature |
| **Judge or visitor** | To see it work and trust it | Re-derive the canary, watch the test canary die, read receipts |
| **Admin (the owner)** | Safe parameter changes | Pause new cover, set the premium rate; every admin action needs ML-DSA |

## User stories (P0 unless marked)

### Canary
- As a visitor, I can see each canary's status (alive or dead), its address, the phrase it was derived from, and a one-click way to re-derive it in the browser.
- As a reporter, I can submit a canary signature. If valid, the canary is marked dead, the time is recorded, and I receive the bounty.
- As a visitor, I can tell the **test canary** apart from the **real canary** everywhere in the UI.

### Liquidity
- As an LP, I can deposit QOR and receive pool shares. My account must have a registered ML-DSA-87 key with proof of possession, or the deposit is refused, so I can always withdraw later.
- As an LP, I can request a withdrawal, signed with ML-DSA. After the cooldown, I can execute it, also signed, to a recipient address I choose.
- As an LP, I can see the share price, my share value, pool utilisation and premiums earned.

### Cover
- As a buyer, I can pick a cover amount and duration, see the premium, and buy. The policy is owned by an account with a registered ML-DSA key.
- As a buyer, I can see my policies with status: active, expired, claimable, or paid.
- As a buyer, after the canary dies, I can claim my payout to a recipient I choose, authorised by my ML-DSA signature.

### Admin
- As the admin, I can pause and unpause new cover, and change the premium rate, each authorised by my ML-DSA signature. Pausing never blocks withdrawals or claims.

### P1
- As a buyer, I can attach a **sealed policy note** (for example, which wallets I'm hedging), encrypted with QoreSeal (ML-KEM-1024) to me and an auditor key. Only a hash goes on-chain.
- As a visitor, I can see a live activity feed of deposits, cover purchases, withdrawals and claims.

### P2 (only if the owner asks)
- Multiple real canaries (for example a second hash-to-curve phrase, or another curve).
- Selling cover in fUSD instead of QOR.

## Scope

| Priority | In scope |
|---|---|
| **P0** | CanaryRegistry, CoverPool (one per canary), ML-DSA authorisation on withdraw, claim and admin actions, scoped EVM windows, Foundry tests, two-stage QCAI audit, canary derivation script, test canary and kill script, web app (status, LP, cover, claim), testnet deployment, README, threat model, AI_USAGE.md, demo video |
| **P1** | QoreSeal sealed policy notes, activity feed, a "verify the canary" page with step-by-step derivation |
| **P2** | More canaries, fUSD pools |

## Non-goals

- Mainnet deployment, real money, or any regulatory claim. This is a testnet demonstration; the UI says "cover" and "testnet" and never "insurance".
- Proving a policyholder's personal loss.
- Price oracles, external data or governance tokens.
- A mobile app. Desktop browser with the QoreX extension and an EVM wallet only.

## Success criteria for the submission

1. All four category requirements are visibly met and explained in the README, each with a link to the code or a tx.
2. On testnet, the full story works end to end: LP deposits, a buyer buys cover, the test canary is killed, the buyer claims with an ML-DSA signature, the LP withdraws the remainder.
3. A judge can re-derive the real canary from its phrase and get the same address.
4. Every pre-judging check passes (see `09_SUBMISSION.md`).
5. A demo video of 3 minutes or less tells the story above.

## Product decisions (fixed)

| Decision | Choice | Why |
|---|---|---|
| Pool asset | Native QOR (18 decimals on the EVM lane) | No ERC-20 conversion step; faucet pays QOR directly |
| Collateral | Fully collateralised: total active cover ≤ pool assets | Every claim is payable; simplest correct design |
| Premium | Flat annual rate in basis points, pro-rata by duration | Easy to explain and test |
| Policy duration | Configurable min/max; demo pool allows minutes | The demo must expire and trigger inside a video |
| Pools | One CoverPool per canary (real and test) | Test-canary money never mixes with real-canary money |
| Withdrawal | Request, cooldown, then execute | Stops LPs from front-running a canary claim |
| Claim window | Fixed period after the trigger; leftovers return to LPs after it | Pool must eventually settle |
| Bounty | Paid to the reporter from free capital only, capped | Rewards reporting without reducing payouts |
