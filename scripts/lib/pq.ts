/**
 * Track B ML-DSA-87 signing (plan 02/06): the canonical PQ key derived from the account mnemonic with
 * @qorechain/qoresign deriveCanonicalPqKey (== the key registered on-chain, proven in SPIKE S1), signing the
 * raw 32 digest bytes with @qorechain/pqc (msgMode RAW, D-001). Demo accounts only; keys come from .env.
 */
import { mldsa } from "@qorechain/pqc";
import { deriveCanonicalPqKey } from "@qorechain/qoresign";
import { bytesToHex, hexToBytes, parseAbi, type Address, type Hex } from "viem";
import { ACCOUNT_NAMES, config, mnemonicVar, type AccountName } from "../config.js";
import { requireEnv } from "./env.js";
import { publicClient } from "./evm.js";
import { loadAccount } from "./qore.js";

const pqcAbi = parseAbi([
  "function pqcKeyStatus(address account) view returns (bool registered, uint8 algorithmId, bytes pubkey, bool possessionProven)",
  "function pqcVerify(bytes pubkey, bytes signature, bytes message) view returns (bool valid)",
]);

/** Which demo account owns `owner` (0x address). */
export async function accountNameFor(owner: Address): Promise<AccountName> {
  for (const n of ACCOUNT_NAMES) {
    if ((await loadAccount(n)).evm.toLowerCase() === owner.toLowerCase()) return n;
  }
  throw new Error(`${owner} is not one of the demo accounts in .env (${ACCOUNT_NAMES.join(", ")}).`);
}

export async function onchainPqKey(owner: Address): Promise<Hex> {
  const [registered, algo, pubkey, proven] = await publicClient.readContract({
    address: config.precompiles.pqcKeyStatus,
    abi: pqcAbi,
    functionName: "pqcKeyStatus",
    args: [owner],
  });
  if (!registered || algo !== 1 || !proven) throw new Error(`${owner} has no registered, proven ML-DSA-87 key.`);
  return pubkey;
}

/** Sign a 32-byte digest as `name`. Verifies locally and via pqcVerify eth_call before returning. */
export async function pqSignDigest(name: AccountName, digest: Hex): Promise<Hex> {
  const d = hexToBytes(digest);
  if (d.length !== 32) throw new Error("Digest must be exactly 32 bytes (0x + 64 hex chars).");
  const a = await loadAccount(name);
  const key = deriveCanonicalPqKey({ mnemonic: requireEnv(mnemonicVar(name)), address: a.cosmos });
  const sig = mldsa.sign(key.secretKey, d);
  const onchain = await onchainPqKey(a.evm as Address);
  if (onchain.toLowerCase() !== bytesToHex(key.publicKey)) {
    throw new Error(`The key derived for ${name} is not the key registered on-chain for ${a.evm}.`);
  }
  if (!mldsa.verify(key.publicKey, d, sig)) throw new Error("Local ML-DSA verification failed.");
  const ok = await publicClient.readContract({
    address: config.precompiles.pqcVerify,
    abi: pqcAbi,
    functionName: "pqcVerify",
    args: [onchain, bytesToHex(sig), digest],
  });
  if (!ok) throw new Error("pqcVerify returned false for this signature.");
  return bytesToHex(sig);
}
