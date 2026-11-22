# Spikes

Every open question from `docs/plan/` settled against **qorechain-diana testnet** (EVM chain 9800). Each spike lists its exact command, output, tx hashes and conclusion. Full raw output is in `docs/spike-logs/`.

Environment facts checked on 2026-11-22 (block ≈ 10,574,244):

| Fact | How checked | Result |
|---|---|---|
| EVM chain ID | `eth_chainId` on `https://evm-testnet.qore.host` | `0x2648` = 9800 ✓ |
| Chain version | `https://download.qore.host/testnet/latest.json` | `3.2.8` |
| Active precompiles | `curl -s https://api-testnet.qore.host/cosmos/evm/vm/v1/params \| jq .params.active_static_precompiles` | `0x…0901`, `0x…0C01`, `0x…0a01`, `0x…0a02` ✓ (matches plan) |
| Protocol features | `GET /qorechain/pqc/v1/protocol_features` | `pqc-sign-bytes-v2`, `evm-pqc-authorisation-window`, `evm-unprotected-tx-refusal` enabled |
| Kit package names | `npm view @qorechain/<pkg> version` | sdk 0.14.0, pqc 0.2.3, qoresign 0.2.0, qorex-rainbowkit 0.1.0, qoreseal 0.1.0, qorex-wallet-mock 0.1.0 — all exist |

### APIs used, and where each was verified (AGENT_BRIEF §1.1)

All verified in the installed package's own type declarations / README (not from memory):

| API | Source |
|---|---|
| `deriveUnifiedAccount(mnemonic)` — eth_secp256k1, HD path `m/44'/60'/0'/0/0` | `@qorechain/sdk` 0.14.0 `dist/index.d.ts` + README "Unified eth-native wallet" |
| `EthNativeSigner` (`signMode: "classical" \| "hybrid"`) | sdk `index.d.ts` |
| `buildRegisterPqcKeyMsg`, `signProofOfPossession`, `fetchPqcStatus` | sdk `index.d.ts` |
| `openEvmWindowMsg` (`allowedTargets`, `nativeOnly`), `closeEvmWindowMsg`, `fetchEvmWindow`, `classifyEvmWindowRejection` | sdk `index.d.ts`, `@qorechain/evm/dist/window.d.ts` |
| `deriveCanonicalPqKey({ mnemonic, address })` | `@qorechain/qoresign` 0.2.0 `dist/*.d.ts` |
| `mldsa.sign / verify` (ML-DSA-87, deterministic default) | `@qorechain/pqc` 0.2.3 `src/index.d.ts` + README |
| REST `POST /cosmos/tx/v1beta1/txs`, `GET /cosmos/auth/v1beta1/accounts/{addr}` | standard Cosmos SDK; probed live |

---

## S1 — Accounts, ML-DSA-87 registration with proof, derived == on-chain pubkey

**Status: PARTIAL — offline half PASS; on-chain half BLOCKED on faucet funds (owner).**

Accounts were created with the SDK instead of `qorechaind keys add` (same key type: eth_secp256k1, coin type 60; see `DECISIONS.md` D-002):

```text
pnpm accounts create
deployer  qor1l69nm6wn5s999z4t0wtxum3xm58x3z4wghxvu9  0xfE8b3De9D3A40a528aaB7B966e6e26DD0e688aae
lp1       qor15uwachj8qyczfrfedktxkx2keulhe8htlhmwk9  0xa71ddC5e470130248D396d966b1956CF3f7c9eEb
buyer1    qor1fhmw6u03zl0llvhxfk4hfzsxrua8reftcxtzjj  0x4DF6ED71f117dfFfB2e64Dab748A061f3A71e52B
reporter  qor1lp0nlay9uredcr965rfetem4chm9nrw8uqpwfz  0xf85f3fF485e0F2Dc0CBaA0D395e775c5f6598Dc7
```

**Offline check** — the key the SDK registers (`deriveUnifiedAccount(...).pqc`) equals the key Track B signs with (`qoresign.deriveCanonicalPqKey`):

```text
pnpm --filter scripts spike:s1:local
deployer  pubkey 2592B keccak=0x5d44d7e9191ae358… qoresign==sdk: true
lp1       pubkey 2592B keccak=0x2c47f699f5e73316… qoresign==sdk: true
buyer1    pubkey 2592B keccak=0x8f0034b8c889406c… qoresign==sdk: true
reporter  pubkey 2592B keccak=0x9118dd3a2300998e… qoresign==sdk: true
```

**On-chain (pending):** `pnpm --filter scripts spike:s1` registers each key via `MsgRegisterPQCKeyV2` (classical-signed bootstrap, `keyType: "hybrid"`, with `proofOfPossession`), then reads `pqcKeyStatus(0x…)` through `eth_call` and requires `(true, 1, <2592 bytes>, true)` plus on-chain pubkey == SDK pubkey == qoresign pubkey.

| Account | Registration tx | pqcKeyStatus | Result |
|---|---|---|---|
| deployer | _pending_ | | |
| lp1 | _pending_ | | |
| buyer1 | _pending_ | | |
| reporter | _pending_ | | |

Observed already: `pqcKeyStatus` on an **unregistered** account returns 160 bytes (`registered=false`, empty `pubkey`), so PQAuth's "returndata ≥ 128 bytes" check holds and decoding then rejects on `registered == false`.

## S2 — Deploy route, scoped window admits targets / refuses others

**Status: BLOCKED on S1 (needs a funded, registered deployer).** Ready to run.

- Contracts: `contracts/test/spikes/Counter.sol`, `contracts/test/spikes/PQProbe.sol` (PQProbe calls both precompiles with low-level `staticcall` + length checks, the PQAuth pattern). `forge build` passes.
- Route A (viem): `pnpm --filter scripts spike:s2` — opens an unscoped window, deploys both with explicit gas (1.5M), checks on-chain runtime code == artifact `deployedBytecode`, opens a window scoped to `[PQProbe]`, calls `PQProbe.probe(sig, digest)` with a real ML-DSA-87 signature (expected: admitted), then `Counter.increment()` (expected: refused, pqc code 27). Writes `deployments/spikes.json`.
- Route B (forge script): to try after route A, with `--skip-simulation --gas-limit` as the plan suggests. Command and outcome will be recorded here.

| Step | Tx | Result |
|---|---|---|
| Unscoped window | _pending_ | |
| Counter deploy | _pending_ | |
| PQProbe deploy | _pending_ | |
| Scoped window `[PQProbe]` | _pending_ | |
| Allowed `PQProbe.probe` | _pending_ | gas used: |
| Refused `Counter.increment` | n/a | error / code: |

## S3 — pqcVerify with real ML-DSA-87 signatures

### Track B (raw 32-byte digest) — **PASS** (2026-11-22)

```text
pnpm --filter scripts spike:s3b
chainId=9800 block=10574244
pubkey=2592B sig=4627B digest=0xbe22233bde4f326d6d1f52746379d9ab7d2123d727d99c464772e7389156950b
local mldsa.verify: true
valid sig, raw 32-byte digest      returndata=0x…0001 gas=312560
tampered digest                    returndata=0x…0000 gas=312560
wrong pubkey (lp1)                 returndata=0x…0000 gas=312440
sig + 1 trailing byte              returndata=0x…0000 gas=312560
hedged (randomised) sig            returndata=0x…0001 gas=312470
pqcKeyStatus(deployer, unregistered) returndata 160B = (false, 0, 0x, false)
inactive precompile 0x…0800 returndata: null
S3 TRACK B: PASS
```

(Full log: `docs/spike-logs/s3-trackb-2026-11-22.log`.) Signature from `mldsa.sign(secretKey, digest)` (`@qorechain/pqc`, key from the account mnemonic). A read-only `eth_call` proves the precompile's verdict; it needs no window or registration. The on-chain tx version runs inside S2 (`PQProbe.probe`).

Conclusions:
1. `pqcVerify(pubkey, mldsa.sign(sk, digest), digest)` returns `true` for the raw 32 digest bytes: **`MODE_RAW` works.**
2. Tampered message, wrong key and a signature with one trailing byte all return `false` (no revert), as documented.
3. Hedged and deterministic signatures both verify.
4. **Gas is much higher than the plan's figure.** A direct `pqcVerify` call estimates at ~312k gas, against the plan's "about 85,000–90,000 per call". An authorised Canary call will probably need ~400k+. S2 measures the real in-contract figure. See `DECISIONS.md` D-004.
5. An inactive precompile returns success with **empty** data: confirms PQAuth must fail closed on short returndata.

### Track A (QoreX `signArbitrary`) — **PENDING (owner, browser)**

Tool: `pnpm --filter scripts spike:page` → open `http://localhost:5174` with QoreX installed. The page signs the fixed digest `0x8404311f59f0ac17137acf43cf0fa749412488e891cdb0bc48c9915252776ecc` with each candidate encoding (`"0x"+hex` string, hex string without `0x`, raw `Uint8Array`). It reports the return shape and encoding (hex or base64), then tries `pqcVerify` with `prefix‖data`, `data` and the raw digest, using the QoreX account's on-chain key. The page's ABI and bech32 code was self-checked against the live precompile (`spikes/browser/selfcheck.ts` → PASS).

## S4 — MetaMask tx on chain 9800 inside a scoped window

**Status: BLOCKED on S1/S2 + owner (MetaMask).** Ready: the same spike page, section S4 (adds/switches chain 9800, sends `Counter.increment()`). Then `pnpm --filter scripts spike:s4 <hash>` parses the receipt with viem and lists any non-standard receipt fields (e.g. `feePayer`).

## S5 — eth_getLogs max block range — **PASS** (2026-11-22)

```text
pnpm --filter scripts spike:s5
head=10574259
range     100: OK   0 logs, 233 ms
range    1000: OK   11 logs, 100 ms
range    5000: OK   192 logs, 269 ms
range   10000: OK   501 logs, 390 ms
range   50000: FAIL Details: maximum [from, to] blocks distance: 10000
…binary search…
S5 RESULT: max eth_getLogs range = 10001 blocks
```

Conclusion: the public RPC enforces `toBlock − fromBlock ≤ 10,000`. The app's and scripts' log readers page in chunks of `to = from + 9,999`, starting from the deployment block.
