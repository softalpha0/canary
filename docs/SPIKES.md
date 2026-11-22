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

**Status: PASS (2026-11-22)** — all 4 accounts registered with proof of possession; on-chain key == SDK key == qoresign key.

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

**On-chain** — `pnpm --filter scripts spike:s1` sends `MsgRegisterPQCKeyV2` (classical-signed bootstrap via `EthNativeSigner`, `keyType: "hybrid"`, with `proofOfPossession`). It then reads `pqcKeyStatus(0x…)` via `eth_call` and requires `(true, 1, <2592 bytes>, true)` and on-chain pubkey == SDK pubkey == qoresign pubkey:

```text
deployer: MsgRegisterPQCKeyV2 tx 68C64149B3BB9369F3725C6B7E0C04348B690202F021DE8489795A8CA227D7CC height 10575411
  pqcKeyStatus(0xfE8b3De9D3A40a528aaB7B966e6e26DD0e688aae) = (true, 1, <2592 bytes>, true)  onchain==sdk: true  onchain==qoresign: true  → PASS
lp1: MsgRegisterPQCKeyV2 tx 54293291CE0C7FA4A2C98FA18565C678B1F79245854ADDA3B82492AE7170FB22 height 10575431
  pqcKeyStatus(0xa71ddC5e470130248D396d966b1956CF3f7c9eEb) = (true, 1, <2592 bytes>, true)  onchain==sdk: true  onchain==qoresign: true  → PASS
buyer1: MsgRegisterPQCKeyV2 tx E3C64EC3FC3445D23217AF343C95E685D48EB58FA4BADB8A7884F2EB4AF1EE55 height 10575433
  pqcKeyStatus(0x4DF6ED71f117dfFfB2e64Dab748A061f3A71e52B) = (true, 1, <2592 bytes>, true)  onchain==sdk: true  onchain==qoresign: true  → PASS
reporter: MsgRegisterPQCKeyV2 tx B0782133FF8788A59569ADB3B9150746A36EAC701B9943E41B670227D491CD67 height 10575435
  pqcKeyStatus(0xf85f3fF485e0F2Dc0CBaA0D395e775c5f6598Dc7) = (true, 1, <2592 bytes>, true)  onchain==sdk: true  onchain==qoresign: true  → PASS
S1: PASS
```

Funding: the owner claimed 100 QOR from the faucet into `deployer`. Deployer then sent QOR to the others with **hybrid ML-DSA-87-signed** bank sends (`pnpm accounts fund`), which is also evidence for the "hybrid ML-DSA-87 transactions" network feature:

| Transfer | Tx | Height |
|---|---|---|
| deployer → lp1, 30 QOR | `05E29506AC77201FBD93BE44A204019D4F47DD8403AEDE05DC6B4EBAEA675E8A` | 10575420 |
| deployer → buyer1, 10 QOR | `A0441F4BFBF24864FC53754C6171822EA55F088BC48160DEE3B0514332069EEB` | 10575423 |
| deployer → reporter, 5 QOR | `040CB8EB3B9939BB2C81FC3E31580408AB25E62936452FFA30AAFD67B70ECB53` | 10575426 |

Also observed: `pqcKeyStatus` on an **unregistered** account returns 160 bytes (`registered=false`, empty `pubkey`), so PQAuth's "returndata ≥ 128 bytes" check holds and decoding then rejects on `registered == false`.

## S2 — Deploy route, scoped window admits targets / refuses others

**Status: PASS (2026-11-22).** Both deploy routes work; the scoped window admits the listed target and refuses a non-target.

### Route A — viem (`pnpm --filter scripts spike:s2`)

```text
fees: maxFeePerGas=132500000000 maxPriorityFeePerGas=12500000000
unscoped window: tx 610C8E8E59BB66F44D4C109A161F34F655D9470C9CD9DEE2E5D0AE496A19BA96 height 10575443
Counter: 0x66b774a7c51089162cfcab2eade7c624135f3a9c tx 0xc3fdc329272b0dfa21fe00c9dde2812292b4d93437ed4f55fcda9073b1146469 block 10575451 gasUsed 750000 runtimeCodeMatches=true
PQProbe: 0xc8815608dbf829a9a42e80c3392c17b091a85e0f tx 0x29b69e0eb0cf9672604267e7318e2efeb00f4c5cc10e5951f7329bdd8c1db76f block 10575452 gasUsed 750000 runtimeCodeMatches=true
scoped window (targets=[PQProbe]): tx F9D069B98D065C53EEF2FD9F85C78A88280C913700823672724022C8EA1017F6 height 10575453
window: live=true targets=0xc8815608dbf829a9a42e80c3392c17b091a85e0f remainingTxs=4
ALLOWED PQProbe.probe: tx 0x45cbdf4f64b719ec1c4f45ff13f583fd2db7822cae405267346b0237fc8085e6 status success gasUsed 500000
  event KeyStatus {"account":"0xfE8b…8aae","registered":true,"algorithmId":1,"pubkeyLength":"2592","proven":true}
  event Verified {"caller":"0xfE8b…8aae","valid":true,"gasUsed":"153786"}
REFUSED Counter.increment (non-target): failed to broadcast transaction: the EVM authorisation window for qor1l69nm6wn5s999z4t0wtxum3xm58x3z4wghxvu9 does not admit this transaction: the window does not list 0x66B774a7C51089162CFCAB2Eade7C624135f3A9c as an allowed recipient: EVM authorisation window exhausted  classify=exhausted
window after: usedTxs=1 remainingTxs=3 usedValue=132500uqor
S2: PASS
```

The allowed tx is also the **first on-chain PQ-authorised call**: a contract looked up the sender's registered ML-DSA-87 key with `pqcKeyStatus` and verified a real signature with `pqcVerify` inside a transaction (`valid: true`).

### Route B — `forge script` (`tsx scripts/forge-script.ts --account deployer -- script/SpikeDeploy.s.sol:SpikeDeploy --broadcast --skip-simulation --gas-estimate-multiplier 130`)

From a fresh unscoped window (`264D73FFD5069FA662D87EE5AE83D0245A815602D58014EA3BB223832F49E002`): `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL`. Counter at `0x95D0A6F4E64989336B776d142AbAf5C675280A3B`, tx `0xdb5af29daf64fbcaba0d04be865786a43deb7b5ba0eb2973227357499a9a6362`, block 10575513, status 1, gasUsed 109,605; on-chain code == artifact. The key reaches forge only via the child process's `PRIVATE_KEY` env (`vm.envUint`); it is never printed.

**Caveat:** forge still executes the script locally before broadcasting, and local EVMs have no `0x…0a02`. CoverPool's constructor calls `pqcKeyStatus(admin)`, which would fail closed there. **Primary deploy route for Canary: viem (`scripts/deploy.ts`)**, the route proven above.

### Findings that change implementation details

1. **Refusal code.** The EVM JSON-RPC returns the refusal as text, not a numeric `pqc` code. The text names the code-27 error ("EVM authorisation window exhausted") and the reason ("does not list 0x… as an allowed recipient"). `classifyEvmWindowRejection` maps an **out-of-scope** refusal to `"exhausted"`, so the app must also match "does not list … as an allowed recipient" and tell the user to open a window that includes Canary's contracts, not just "open a new window".
2. **Gas: the chain charges at least 50% of the gas limit.** Every receipt shows `gasUsed = gasLimit × 0.500` (1.5M → 750,000; 1M → 500,000), although real needs are much lower (`spike-logs/s2-gas.log`): deploy Counter 109,605, deploy PQProbe 526,146, **PQ-authorised call (`probe`, 4,627-byte sig) 235,076**. In-contract `pqcKeyStatus` + `pqcVerify` cost 153,786. Gas limits must be set from `eth_estimateGas × 1.25`, not padded flat limits. See `DECISIONS.md` D-004.
3. Window value accounting matches the docs: one admitted tx with a 1,000,000 gas limit at 132.5 gwei used 132,500 uqor of `maxValue`.

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

(Full log: `docs/spike-logs/s3-trackb-2026-11-22.log`.) Signature from `mldsa.sign(secretKey, digest)` (`@qorechain/pqc`, key from the account mnemonic). A read-only `eth_call` proves the precompile's verdict; it needs no window or registration. The on-chain tx version ran in S2 (`PQProbe.probe`, tx `0x45cbdf4f…85e6`, `valid: true`).

Conclusions:
1. `pqcVerify(pubkey, mldsa.sign(sk, digest), digest)` returns `true` for the raw 32 digest bytes: **`MODE_RAW` works.**
2. Tampered message, wrong key and a signature with one trailing byte all return `false` (no revert), as documented.
3. Hedged and deterministic signatures both verify.
4. Gas: a bare `pqcVerify` `eth_call` estimates at ~312k. **Superseded by S2:** inside a tx, key lookup + verify cost ~154k, and a full PQ-authorised call ~235k (see S2 findings, `DECISIONS.md` D-004).
5. An inactive precompile returns success with **empty** data: confirms PQAuth must fail closed on short returndata.

### Track A (QoreX `signArbitrary`) — **NOT SETTLED; skipped by owner (2026-11-22)**

What the owner's browser runs showed (spike page, QoreX desktop extension, account `qor1skjtefn4thsq8zz039azumk8h6g480jx3gfk0c`, whose key is registered and proven):

- `window.qorex.native` exposes `signArbitrary` and `verifyArbitrary`. Capabilities: `listAccounts, connectProofPicksAccount, executeRequest, signAndBroadcast, signDirectAddsPqcLayer, signArbitrary`.
- `signArbitrary(chainId, bech32, data)` returns `{signatureType, classical, pq, pub_key, signature}` for a string or `Uint8Array` `data`. **`signature` is the 64-byte classical secp256k1 signature (base64)**; the ML-DSA-87 part is in `pq`. The first run decoded the wrong field, so its `false` results say nothing about Track A.
- The page was fixed to decode `pq` (tested end to end against a mock QoreX with a real ML-DSA-87 signature: `prefix ‖ data` → `pqcVerify` TRUE, `spikes/browser/mock-qorex-check.ts`). The re-run against real QoreX did not complete (no signing prompts approved). The owner chose to skip it.

**Conclusion:** no QoreX encoding is proven, so `msgMode = MODE_RAW` is final (D-001). The app ships Track B ("Sign with the Canary CLI" modal), as plan 08's cut order allows. Track A can be revisited later with the same page; the leading candidate is `prefix ‖ utf8(data)` with the signature in `ret.pq`.

## S4 — EVM tx on chain 9800 inside a scoped window, receipt parsed by viem

**Status: PASS via script; MetaMask UI part waived by owner (2026-11-22).** See `DECISIONS.md` D-008.

The owner's MetaMask connected to chain 9800 (`eth_chainId` = `0x2648`, chain added by the page), but on a non-deployer account, so no tx was sent from MetaMask. The owner chose to skip the MetaMask run. The same transaction was sent from deployer's eth_secp256k1 key with viem inside the scoped window (tx `5BFC8518…993E`, targets Counter + PQProbe):

```text
pnpm --filter scripts exec tsx spikes/s4-viem-fallback.ts && pnpm --filter scripts spike:s4 <hash>
Counter.increment from deployer via viem: 0xa2db35a1d8a36eaa5bc8e2b574c21285bfbd644ba37398176041f96d80a8e5d4 (gas limit 56185)
tx 0xa2db35a1…e5d4: from 0xfe8b…8aae to 0x66b7…3a9c type eip1559 chainId 9800 nonce 12
receipt: status success block 10577106 gasUsed 44948 effectiveGasPrice 112500000000
non-standard receipt fields: none
event Incremented {"by":"0xfE8b3De9D3A40a528aaB7B966e6e26DD0e688aae","number":"1"}
S4: PASS
```

Proven: a scoped window admits an EIP-1559 tx from the account's EVM key on 9800, and viem parses the receipt (no `feePayer` or other non-standard fields appeared). Not proven: MetaMask's own signing and sending on this chain. M3 will exercise it, since the web app sends through MetaMask.

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
