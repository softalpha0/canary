# 05 — QoreChain Integration

Facts below come from docs.qorechain.io, build.qorechain.io and kit READMEs as read on 21 Nov 2026. QoreChain changes often: **re-check anything you depend on**, and record what you proved in `docs/SPIKES.md`.

## Network (testnet only)

| Item | Value |
|---|---|
| Cosmos chain ID | `qorechain-diana` |
| EVM chain ID | `9800` |
| EVM JSON-RPC | `https://evm-testnet.qore.host` |
| Cosmos RPC | `https://rpc-testnet.qore.host` |
| REST | `https://api-testnet.qore.host` |
| Explorer | `https://explore.qore.network` (switch to Testnet). No source verification, no Etherscan-style API; EVM txs are not searchable from the Cosmos tabs. |
| Native token | QOR. Bank denom `uqor` has 6 decimals; on the EVM lane balances use 18 decimals (1 QOR = 1e18 wei). |
| Gas | EIP-1559 base fee; floor 0.1 uqor per gas. Max 30,000,000 gas per tx. Set explicit gas limits; estimation can fail. |
| Block time | About 1.3 s on testnet (varies). EVM window lengths are counted in blocks. |
| Active precompiles (testnet) | `0x…0901` (allowlist), `0x…0a01` (pqcVerify), `0x…0a02` (pqcKeyStatus), `0x…0c01`. Standard Cosmos precompiles (staking 0x800, etc.) are **not** active. Inactive addresses return success with **empty data**. |
| Caveats | `BLOCKHASH` is zero inside EVM txs. Unprotected (pre-EIP-155) txs are refused. Receipts may include a non-standard `feePayer` field that some tools misread. |

Check active precompiles: `curl -s https://api-testnet.qore.host/cosmos/evm/vm/v1/params | jq .params.active_static_precompiles`

## The EVM gate: key + window

The EVM lane admits a transaction only from an account that has **(1)** a registered ML-DSA-87 key and **(2)** an open **EVM authorisation window** with room left. Reads (`eth_call`, `eth_getLogs`, gas estimation) need neither.

### Accounts

- Use `eth_secp256k1` keys with coin type 60. A plain Cosmos `secp256k1` account cannot sign for its EVM address.
  `qorechaind keys add <name> --key-type eth_secp256k1 --coin-type 60`
- The `0x…` and `qor1…` forms are the same account. Convert with the SDK or `qorechaind debug addr`.

### ML-DSA-87 key registration (once per account, about 0.09 QOR)

- **SDK (preferred, matches Track B):** `ensurePqcRegistered(...)` from `@qorechain/sdk` registers the account's canonical PQ key (derived from the mnemonic). It is safe to re-run, and stops if a different key is already registered.
- **CLI:** `qorechaind tx pqc gen-key mypqc` then `qorechaind tx pqc register-key-v2 dilithium5 <pubkey-hex> hybrid --pqc-key mypqc --from <name> --chain-id qorechain-diana --gas 600000 --fees 60000uqor -y`. The CLI key lives unencrypted at `~/.qorechaind/pqc/mypqc.dilithium`. Never commit it.
- **Always register with proof of possession.** CoverPool refuses keys without it.
- Check: `curl -s https://api-testnet.qore.host/qorechain/pqc/v1/account/<qor1…>` (fields: `found`, `public_key`, `algorithm_name` = `dilithium5`, `possession_proven`), or `pqcKeyStatus(0x…)` via `eth_call`.
- Registration errors: 230 (weak or classical-only), 231 (proof invalid), 232 (key used before), 45 (classical key mismatch).

**Pick one registration route per account and keep it.** Track B signing must use the same secret key that is registered: either the SDK's canonical derived key (`deriveCanonicalPqKey({ mnemonic, address })` from `@qorechain/qoresign`) or the CLI key file. Spike S1 confirms the derived public key equals the on-chain one.

### EVM windows

- Opened by a hybrid-signed Cosmos message (`MsgOpenEVMWindow`). Opening replaces the previous window. Wait about 10 s (it advances the nonce) before sending EVM txs.
- Bounds, all required: blocks 1–17,280 (about 6 h on testnet); max txs 1–1,000; max value > 0 in uqor, which counts native QOR sent **plus** each tx's max fee. A failed but admitted tx still uses its slot and budget.
- Scope: `--native-only` (plain QOR transfers only) or `--allowed-targets 0xA,0xB` (recipients must be listed; **contract creation is refused**). Never list routers or forwarders.
- CLI example (from the docs, adapt the chain ID to `qorechain-diana`):
  ```text
  qorechaind tx pqc open-evm-window <blocks> <max-txs> <max-value> --allowed-targets 0xREG,0xPOOL0,0xPOOL1 \
    --from <name> --chain-id qorechain-diana --gas 400000 --fees 40000uqor --generate-only > w.json
  qorechaind tx pqc cosign w.json --from <name> --pqc-key <pqc-name> --chain-id qorechain-diana
  ```
  then broadcast the cosigned tx. Close early with `qorechaind tx pqc close-evm-window`.
- SDK: `openEvmWindowMsg` (0.9.0+ supports `nativeOnly` and `allowedTargets`), `fetchEvmWindow({ rest, address })`, `classifyEvmWindowRejection(err)` → `"no-pqc-key" | "no-window" | "exhausted" | "invalid"`.
- Read the window: `GET /qorechain/pqc/v1/evm_window/{address}` or `qorechaind query pqc evm-window <address>`.
- Refusal codes (codespace `pqc`): 26 no window or no key; 27 expired, exhausted or out of scope; 28 invalid bounds or no key.
- The FAQ says key registration and window opening can also be done from the Dashboard or QoreX; exact buttons are undocumented.

**Canary's window policy:**
- Deploys: an **unscoped** window on `deployer` (creation is refused under `--allowed-targets`).
- Everything else: a **scoped** window with `--allowed-targets <registry>,<pool0>,<pool1>`. This is what the category means by "scoped EVM window". Use it for every demo account, and show it in the README with the tx hashes.
- Ship `scripts/window.ts` with `status`, `open-scoped`, `open-deploy` and `close` subcommands (SDK first, CLI fallback), so a judge can reproduce it.

## Precompiles

See `03_SMART_CONTRACTS.md` for interfaces. Key points:
- `pqcVerify` takes the **raw message bytes** (FIPS 204 pure ML-DSA-87, empty context). Apps sign a 32-byte digest and pass those 32 bytes (Track B).
- QoreX `signArbitrary` signs `"qorechain-msg-v1|" + chainId + "|" + data`. To verify on-chain, pass the prefixed bytes (Track A, spike S3).
- Typed Solidity calls revert on empty returndata; Canary uses low-level `staticcall` with explicit length checks so the failure reason is clear.
- Active on testnet only; mainnet calls return empty data, so Canary fails closed.

## Wallets in the browser

- **EVM transactions:** QoreX's EVM provider answers account and chain queries only. It **does not sign or send EVM transactions** today (README: personal_sign, typed data and transactions are "planned"). So the app sends EVM txs through an injected EVM wallet (MetaMask) holding the account's `eth_secp256k1` key, imported from the same mnemonic or private key. Add chain 9800 to MetaMask with the RPC above.
- **ML-DSA signatures:** the QoreX desktop extension, `window.qorex.native` (Keplr-style). `enable("qorechain-diana")`, `getKey(...)` → `bech32Address`, `signArbitrary(chainId, bech32Address, data)`. Check `capabilities.includes("signArbitrary")` first. The mobile dApp browser does not support `signArbitrary`.
- **Owner = signer:** the QoreX account that signs must be the **owner** account whose key is registered on-chain. Spike S3 confirms QoreX signs with the same registered key returned by `pqcKeyStatus(owner)`.
- **Packages:** `@qorechain/qorex-rainbowkit` (RainbowKit wallet entry plus viem chain definitions) is optional for account display. `@qorechain/qorex-wallet-mock` and `@qorechain/qorex-synpress` are for browser tests (P1).

## Deploying contracts

Two documented outcomes from other entries: PQ Timelock Vault deployed with `forge script … --rpc-url https://evm-testnet.qore.host --private-key $KEY --gas-limit 3000000 --broadcast`; QVault found `forge script` simulation lacks the `0x0a02` precompile and `forge create` misread receipts, so it deployed with ethers. **Canary's plan:**
1. Try `forge script` with `--skip-simulation` (or `--gas-limit`) and explicit gas. The constructor calls `pqcKeyStatus(admin)`, so local simulation will fail without the precompile.
2. If anything misbehaves, deploy with a viem script (`scripts/deploy.ts`) that reads Foundry artifacts. Record which worked in `docs/SPIKES.md`.
3. After deploy, write every address, tx hash and block number to `docs/DEPLOYMENTS.md` and `deployments/testnet.json` (the app and scripts read this file).
4. No explorer verification exists, so add `scripts/verify-bytecode.ts`: compare on-chain runtime code to the Foundry artifact's `deployedBytecode`, masking immutable references (from the artifact's `immutableReferences`). Link it from the README.

## Faucet and QOR budget

- `https://dashboard.qorechain.io/faucet`: sign in, paste a `qor1…` address. 100 QOR per claim, **once per 24 h per sign-in account and per address**. It also sends fUSD, fETH and fBTC (not used by Canary).
- **One person, one sign-in.** Claim daily into `deployer` and send QOR to your other accounts. Never create extra sign-ins.
- Budget for the whole build (rough): key registrations 4 × 0.1; windows about 0.05 each; deploys about 1–3 QOR in total; about 0.03 per PQ-authorised call; demo pool liquidity 20–40 QOR; real pool liquidity 10–20 QOR. Claiming every day from 21 Nov gives about 1,100 QOR, which is plenty.

## How the hackathon detects what you used

- **Kits** show as *Verified* when the package name appears in a dependency file in the repo (`package.json` and similar). Canary should list, because it really uses them: `@qorechain/sdk`, `@qorechain/pqc` (qorechain-pqc), `@qorechain/qoresign`, and (if used) `@qorechain/qorex-rainbowkit`. P1 adds `@qorechain/qoreseal`. Verify each npm name before installing. Never add a package you don't use.
- **Network features** show as *Verified* when proven by transactions from the `qor1…` addresses listed on the project page: EVM window (including scoped), hybrid ML-DSA-87 transactions, PQC key registration with proof of possession. List all demo accounts' `qor1…` addresses on the project page.
- **Solidity PQC verify and key status** stay *Declared*: jurors check them by hand in the repo. Make them easy to find: README links straight to `PQAuth.sol` and the tests.
- `create-qorechain-dapp` cannot be auto-verified. Use it only if it saves time (see M0).

## Spikes (settle in M0, record in `docs/SPIKES.md`)

| ID | Question | Pass means |
|---|---|---|
| S1 | Can we create `eth_secp256k1` accounts, fund them, and register ML-DSA-87 keys with proof of possession? Does the SDK-derived PQ pubkey equal the on-chain one? | `pqcKeyStatus` returns `(true, 1, <2592 bytes>, true)`; derived pubkey equals on-chain pubkey |
| S2 | Which deploy route works (`forge script` vs viem)? Does a scoped window admit calls to listed targets and refuse others with code 27? | A contract deployed; one allowed call succeeds; one non-target call refused, code recorded |
| S3 | Track B: does `pqcVerify(pubkey, mldsa.sign(sk, digest), digest)` return true via `eth_call`? Track A: which encoding of a 32-byte digest, signed by QoreX `signArbitrary`, makes `pqcVerify` return true with the prefixed message? What does QoreX return (hex or base64)? | Track B true (required). Track A: an exact encoding found, or "not possible" recorded |
| S4 | Can MetaMask (account imported from the same key) send an EVM tx on chain 9800 inside a scoped window, and does viem parse the receipt? | Tx hash plus a parsed receipt |
| S5 | What block range does `eth_getLogs` allow on the public RPC? | Max range recorded; the app's log reader pages accordingly |
