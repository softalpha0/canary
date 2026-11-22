# 06 — Frontend

## Stack

- **Vite + React 18 + TypeScript** (strict), **wagmi v2 + viem** for EVM, **TanStack Query** (comes with wagmi), **Tailwind CSS**, **react-router**.
- `@noble/curves` for in-browser canary re-derivation.
- `@qorechain/sdk` for window and key status (`fetchEvmWindow`, `classifyEvmWindowRejection`) and address conversion. Confirm these exports exist in the installed version.
- QoreX access through `window.qorex.native` behind a small typed wrapper (`src/lib/qorex.ts`). Optionally `@qorechain/qorex-rainbowkit` for the connect modal.
- Static site. No backend. Hosting is the owner's call (Vercel or GitHub Pages); the agent only provides `pnpm --filter app build`.

## Config

`app/src/config.ts` reads `deployments/testnet.json` (copied into `app/src/generated/` by a prebuild script) and `VITE_` env vars: chain 9800, RPC, REST, explorer, registry, pool addresses per canary, deployment block (log reads start there), and `msgMode` from S3.

Define the chain with viem `defineChain` (id 9800, name "QoreChain Testnet", native currency QOR with 18 decimals, RPC `https://evm-testnet.qore.host`), unless `@qorechain/qorex-rainbowkit` already exports one.

## Pages

| Route | Purpose | Key content |
|---|---|---|
| `/` | The pitch at a glance | Hero: "Is ECDSA still alive?" Two canary cards (real, test): status pulse (ALIVE green / DEAD red), address, pool size, active cover, premium rate. "How it works" in 3 steps. Link to the video and the repo. |
| `/setup` | Get an account ready | Checklist, each step live and green or red: (1) EVM wallet on chain 9800; (2) QoreX extension connected (`signArbitrary` available); (3) QoreX account equals the EVM account (compare `qor1` ↔ `0x`); (4) ML-DSA key registered with proof (`pqcKeyStatus`); (5) scoped EVM window open, targets include Canary's contracts, with blocks, txs and value left. Each red step shows the exact fix and a copy button for the `scripts/window.ts` command. |
| `/canary/:id` | Trust the trigger | Status, death time, reporter, the bounty. "Verify this canary yourself": phrase, DST, a "Re-derive in my browser" button, computed vs on-chain address, a match badge. For the test canary: a "TEST" label and how the demo kills it. |
| `/pool/:id` | LP and cover for one canary | Stats: total assets, active cover, free capital, utilisation %, share price, premium rate, paused. **LP panel:** deposit; my shares and value; my withdrawal requests (request, cancel, execute with cooldown countdowns). **Cover panel:** amount and duration inputs, live premium quote, buy. |
| `/policies` | My cover | Policies across both pools: amount, start, expiry, status (active, expired, claimable, paid, lapsed). Claim button when claimable. "Expire" button for expired policies (anyone can call). |
| `/admin` | Admin only (connected account == pool `admin`) | Pause or unpause new cover; set the premium rate. Both PQ-signed. |
| P1 `/activity` | Live feed | Deposits, cover, withdrawals, claims, deaths, newest first, from logs. |

Persistent UI:
- **Top bar:** network badge "QoreChain Testnet", EVM account, QoreX account, window status chip (green "Window: 37 txs left" / amber "Window low" / red "No window").
- **Global banner when a canary is dead:** red, with the time, and "Claims close in hh:mm:ss".
- **Footer:** "Testnet demonstration. Not insurance. No real funds."

## The PQ signing component (most important UI piece)

`<PQAuthorizeButton action owner params onSigned>` handles every authorised action:

1. Read `nonces(owner)` and set `deadline = now + 10 min`.
2. Get the digest from the contract view `actionDigest(action, owner, deadline, paramsHash)`. Never rebuild it in JavaScript alone; if you also compute it in JS for display, assert they match.
3. Get the ML-DSA signature:
   - **Track A (if S3 passed and `msgMode == QOREX`):** `window.qorex.native.signArbitrary("qorechain-diana", ownerBech32, <encoding from S3>)`. Convert the result to `0x…` bytes and check it is 4,627 bytes.
   - **Track B (if `msgMode == RAW`, or QoreX is unavailable):** a modal shows the exact command, `pnpm pq:sign --owner 0x… --digest 0x…`, with a copy button and a textarea for pasting the signature hex. Validate the length (4,627 bytes = 9,254 hex characters).
4. Pre-check with `eth_call` to `pqcVerify` (no window needed). If false, show "Signature does not match the key registered for this account" and stop. This saves the user a failed tx and a window slot.
5. Send the tx through the EVM wallet with an explicit gas limit (start at 600,000; tune from S2 and S4 results).
6. Map errors to plain next steps: window errors via `classifyEvmWindowRejection`, custom errors via the ABI (`CooldownActive` → "Withdrawal unlocks at 14:32").

`scripts/pq-sign.ts` (Track B) loads the owner's mnemonic from `.env` (`<NAME>_MNEMONIC`), derives the canonical PQ key, signs the raw 32-byte digest, checks the signature locally against the on-chain pubkey, and prints the hex. Demo accounts only.

## States every page must handle

Loading; no EVM wallet; wrong chain (offer to switch); QoreX missing; QoreX account different from the EVM account; key not registered or not proven; window missing, exhausted, out of scope or expired; canary dead; pool paused; cooldown active; RPC error (retry with backoff).

## Live updates

Poll every 5 s: canary status, pool stats, and the connected user's policies and requests. The demo depends on this: when `pnpm demo:kill` runs, the page must turn red within 5 s without a reload.

## Look and feel

Dark background, canary yellow (#F5C518) accent, green and red status colours, monospace for addresses and hashes, with copy buttons and explorer links. One clear primary action per panel. Works at 1280 px and down to 768 px. Accessibility: buttons have labels, status is never colour-only (text too), focus states are visible.

## Frontend tests

- Unit (Vitest): premium quote matches the contract formula; digest from JS equals `actionDigest` for fixed inputs (a test vector exported from Foundry); signature length validation; error mapping.
- P1: Playwright with `@qorechain/qorex-wallet-mock` and `@qorechain/qorex-synpress` for a happy-path purchase and claim.
