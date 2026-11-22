/**
 * SPIKE S1 (on-chain): register ML-DSA-87 keys with proof of possession for the given accounts,
 * then prove pqcKeyStatus(0x…) == (true, 1, <2592 bytes>, true) and that the on-chain pubkey equals
 * both the SDK-derived and the qoresign deriveCanonicalPqKey pubkey (the key Track B signs with).
 *
 *   tsx spikes/s1-onchain.ts [deployer lp1 buyer1 reporter]
 */
import { deriveCanonicalPqKey } from "@qorechain/qoresign";
import { bytesToHex, parseAbi, type Hex } from "viem";
import { ACCOUNT_NAMES, config, mnemonicVar, type AccountName } from "../config.js";
import { requireEnv } from "../lib/env.js";
import { publicClient } from "../lib/evm.js";
import { loadAccount, registerPqcKey } from "../lib/qore.js";

const abi = parseAbi([
  "function pqcKeyStatus(address account) view returns (bool registered, uint8 algorithmId, bytes pubkey, bool possessionProven)",
]);
const names = (process.argv.length > 2 ? process.argv.slice(2) : [...ACCOUNT_NAMES]) as AccountName[];
let allOk = true;

for (const n of names) {
  const a = await loadAccount(n);
  const r = await registerPqcKey(a);
  console.log(r.alreadyRegistered ? `${n}: already registered` : `${n}: MsgRegisterPQCKeyV2 tx ${r.txHash} height ${r.height}`);
  const [registered, algorithmId, pubkey, proven] = await publicClient.readContract({
    address: config.precompiles.pqcKeyStatus,
    abi,
    functionName: "pqcKeyStatus",
    args: [a.evm as Hex],
  });
  const onchain = pubkey.toLowerCase();
  const sdk = bytesToHex(a.pqc.publicKey);
  const qoresign = bytesToHex(deriveCanonicalPqKey({ mnemonic: requireEnv(mnemonicVar(n)), address: a.cosmos }).publicKey);
  const ok = registered && algorithmId === 1 && (onchain.length - 2) / 2 === 2592 && proven && onchain === sdk && onchain === qoresign;
  allOk &&= ok;
  console.log(
    `  pqcKeyStatus(${a.evm}) = (${registered}, ${algorithmId}, <${(onchain.length - 2) / 2} bytes>, ${proven})` +
      `  onchain==sdk: ${onchain === sdk}  onchain==qoresign: ${onchain === qoresign}  → ${ok ? "PASS" : "FAIL"}`,
  );
}
console.log(allOk ? "S1: PASS" : "S1: FAIL");
process.exit(allOk ? 0 : 1);
