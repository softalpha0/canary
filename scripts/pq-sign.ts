/**
 * Track B signer — what the app's "Sign with the Canary CLI" modal tells the user to run:
 *   pnpm pq:sign --owner 0x… --digest 0x…
 * Loads the owner's mnemonic from .env (<NAME>_MNEMONIC), derives the canonical ML-DSA-87 key, signs the RAW
 * 32-byte digest, checks the signature locally and with pqcVerify (eth_call) against the on-chain key, and prints
 * the 4,627-byte signature hex (9,256 chars incl. 0x) to paste back. Demo accounts only.
 */
import { parseArgs } from "node:util";
import type { Address, Hex } from "viem";
import { accountNameFor, pqSignDigest } from "./lib/pq.js";

const { values } = parseArgs({ options: { owner: { type: "string" }, digest: { type: "string" } } });
if (!values.owner || !values.digest) {
  console.error("Usage: pnpm pq:sign --owner 0x<owner> --digest 0x<32-byte digest>");
  process.exit(1);
}
try {
  const name = await accountNameFor(values.owner as Address);
  const sig = await pqSignDigest(name, values.digest as Hex);
  console.error(`Signed as ${name} (${values.owner}); verified locally and by pqcVerify. ${(sig.length - 2) / 2} bytes:`);
  console.log(sig);
} catch (e) {
  console.error(`Error: ${(e as Error).message}`);
  process.exit(1);
}
