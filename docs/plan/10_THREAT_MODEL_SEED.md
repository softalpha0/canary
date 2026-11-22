# 10 — Threat Model Seed

Starting content for `docs/THREAT_MODEL.md`. The agent updates it to match the final code (function names, parameters, tests) on 30 Nov, and links each mitigation to a test.

## What we protect

| Asset | Where |
|---|---|
| LP capital and premiums | CoverPool balance |
| Policyholders' right to be paid after the trigger | Policies and `activeCover` |
| The integrity of the trigger | CanaryRegistry |
| Users' post-quantum keys | QoreX extension (Track A) or `.env` on the owner's machine (Track B, demo accounts only) |

## Actors

- **Quantum-capable attacker:** can forge ECDSA (secp256k1) signatures for any exposed public key. Cannot forge ML-DSA-87.
- **Classical attacker:** has stolen some users' ECDSA keys or mnemonics, front-runs transactions, sends arbitrary calldata.
- **Malicious LP:** tries to exit before paying claims.
- **Malicious buyer:** tries to claim twice, claim without eligibility, or claim someone else's policy.
- **Admin:** honest but its classical key may be compromised.

## Trust assumptions

1. Nobody knows the discrete log of the canary point. Basis: RFC 9380 hash-to-curve with a public message and DST, re-derivable by anyone (`verify-canary.ts`, browser panel).
2. ML-DSA-87 is secure against quantum and classical attackers (FIPS 204).
3. QoreChain's `pqcVerify` and `pqcKeyStatus` precompiles behave as documented, and the key registry binds each account to one ML-DSA key with proof of possession.
4. The test canary's key is known to the team. **It proves nothing about Q-Day** and exists only for demos. It has its own pool and is labelled TEST everywhere.

## Threats and mitigations

| # | Threat | Mitigation | Test |
|---|---|---|---|
| T1 | Fake trigger: someone kills the real canary without breaking ECDSA | Only a valid `ecrecover` signature by the hash-to-curve address works; no admin can mark it dead | Registry tests; `demo:try-real` |
| T2 | Post-Q-Day theft: an attacker with broken ECDSA keys sends withdraw or claim txs | Authority comes only from the owner's ML-DSA-87 signature via `pqcVerify`; `msg.sender` is never trusted | PQAuth and pool tests |
| T3 | Signature replay across actions, pools, chains or time | Digest binds domain, chain ID, contract, action, owner, nonce, deadline and params; nonce consumed | PQAuth field-by-field tests; E2E replay |
| T4 | Claim redirection by a front-runner who copies a signed claim | Recipient is inside the signed params; a copied tx still pays the signed recipient | Pool redirect test |
| T5 | Bounty theft by copying the break proof | Reporter address is inside the break digest | Registry test |
| T6 | LP front-runs a visible canary claim to escape | Withdrawals need request → cooldown → execute; locked shares stay exposed; after death, LPs get only `netAssets` | Front-running test |
| T7 | Insolvency: more cover sold than the pool can pay | Fully collateralised: `activeCover ≤ assets` at purchase; withdrawals and bounty only from free assets | Invariant 1 |
| T8 | Share inflation attack on the first deposit | Virtual shares offset; minimum deposit | Inflation test |
| T9 | Reentrancy on payouts | `nonReentrant`; state updated before sending | Reentrancy tests |
| T10 | Inactive precompile returns empty data and is read as "valid" | Low-level calls with length checks; fail closed | Absent-precompile tests |
| T11 | Weak key binding: a registered key without proof of possession | Require `possessionProven` and `algorithmId == 1` | PQAuth tests |
| T12 | Admin abuse or a stolen admin ECDSA key | Admin can only pause new cover and set a capped rate; both need the admin's ML-DSA signature; no access to funds | Admin tests |
| T13 | Liabilities stuck forever after death | Claim window, then anyone can settle and return leftovers to LPs | Settlement tests |
| T14 | Harvest now, decrypt later on sealed policy notes (P1) | QoreSeal ML-KEM-1024; only a hash on-chain | — |
| T15 | Leaked demo secrets | `.env` git-ignored; secret scanning before each push; demo accounts hold only test QOR | CI secret scan |
| T16 | Window abuse: a broad window lets a compromised wallet call anything | Users open windows scoped to Canary's contracts only; the app shows the scope | Spike S2 |

## Out of scope and known limits

- **Parametric, not indemnity:** payouts don't depend on actual losses.
- **A quantum attacker might not report.** Someone who breaks ECDSA could keep quiet and steal from exposed wallets instead. The bounty is an incentive, not a guarantee. Canary detects a break only if it is reported.
- **Other ways ECDSA can fail** (a bad random number generator, side channels) don't trigger the canary; only solving discrete log for this specific point does.
- **One curve.** The canary covers secp256k1 only. Ed25519 and others would need their own canaries (P2).
- Testnet only; the precompiles are inactive on mainnet today, so the contracts fail closed there.
- The QCAI audit is an AI-assisted review, not a professional audit.
