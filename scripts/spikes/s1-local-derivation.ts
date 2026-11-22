/**
 * S1 (offline part): the SDK's deriveUnifiedAccount PQ key must equal
 * @qorechain/qoresign deriveCanonicalPqKey({ mnemonic, address }) — Track B signs with the latter.
 */
import { deriveCanonicalPqKey } from "@qorechain/qoresign";
import { ACCOUNT_NAMES, mnemonicVar } from "../config.js";
import { requireEnv } from "../lib/env.js";
import { loadAccount } from "../lib/qore.js";
import { bytesToHex, keccak256 } from "viem";

let ok = true;
for (const n of ACCOUNT_NAMES) {
  const a = await loadAccount(n);
  const k = deriveCanonicalPqKey({ mnemonic: requireEnv(mnemonicVar(n)), address: a.cosmos });
  const same = bytesToHex(k.publicKey) === bytesToHex(a.pqc.publicKey);
  ok &&= same;
  console.log(`${n.padEnd(9)} pubkey ${a.pqc.publicKey.length}B keccak=${keccak256(a.pqc.publicKey).slice(0, 18)}… qoresign==sdk: ${same}`);
}
process.exit(ok ? 0 : 1);
