/**
 * SPIKE S3 Track B: does pqcVerify(pubkey, mldsa.sign(sk, digest), digest) return true via eth_call?
 * Also: negative controls, the ABI shape of pqcKeyStatus, and what an inactive precompile returns.
 * Reads only — no funds or window needed.
 */
import { mldsa } from "@qorechain/pqc";
import { createPublicClient, http, keccak256, toBytes, bytesToHex, parseAbi, encodeFunctionData, type Hex } from "viem";
import { config, qoreTestnet } from "../config.js";
import { loadAccount } from "../lib/qore.js";

const abi = parseAbi([
  "function pqcVerify(bytes pubkey, bytes signature, bytes message) view returns (bool valid)",
  "function pqcKeyStatus(address account) view returns (bool registered, uint8 algorithmId, bytes pubkey, bool possessionProven)",
]);
const client = createPublicClient({ chain: qoreTestnet, transport: http() });
const acct = await loadAccount("deployer");
const pk = acct.pqc.publicKey;

// A fixed 32-byte digest (stands in for PQAuth.digest output).
const digest = toBytes(keccak256(toBytes("Canary.v1 spike S3 track B")));
const sig = mldsa.sign(acct.pqc.secretKey, digest);
console.log(`chainId=${await client.getChainId()} block=${await client.getBlockNumber()}`);
console.log(`pubkey=${pk.length}B sig=${sig.length}B digest=${bytesToHex(digest)}`);
console.log(`local mldsa.verify: ${mldsa.verify(pk, digest, sig)}`);

async function verify(label: string, p: Uint8Array, s: Uint8Array, m: Uint8Array) {
  const data = encodeFunctionData({ abi, functionName: "pqcVerify", args: [bytesToHex(p), bytesToHex(s), bytesToHex(m)] });
  const raw = await client.call({ to: config.precompiles.pqcVerify, data });
  const gas = await client.estimateGas({ to: config.precompiles.pqcVerify, data, account: acct.evm as Hex }).catch((e: Error) => `estimate failed: ${e.message.split("\n")[0]}`);
  console.log(`${label.padEnd(34)} returndata=${raw.data} gas=${gas}`);
  return raw.data;
}

const r1 = await verify("valid sig, raw 32-byte digest", pk, sig, digest);
const flipped = Uint8Array.from(digest); flipped[0] = flipped[0]! ^ 1;
const r2 = await verify("tampered digest", pk, sig, flipped);
const other = (await loadAccount("lp1")).pqc.publicKey;
const r3 = await verify("wrong pubkey (lp1)", other, sig, digest);
const r4 = await verify("sig + 1 trailing byte", pk, Uint8Array.from([...sig, 0]), digest);
const hedged = mldsa.sign(acct.pqc.secretKey, digest, { hedged: true });
const r5 = await verify("hedged (randomised) sig", pk, hedged, digest);

// pqcKeyStatus on an unregistered account: ABI shape + returndata length (PQAuth checks >= 128 bytes)
const ks = await client.call({ to: config.precompiles.pqcKeyStatus, data: encodeFunctionData({ abi, functionName: "pqcKeyStatus", args: [acct.evm as Hex] }) });
console.log(`pqcKeyStatus(deployer, unregistered) returndata ${(ks.data!.length - 2) / 2}B = ${ks.data}`);

// Inactive precompile (staking 0x...0800 is documented as NOT active): expect success + empty data.
const inactive = await client.call({ to: "0x0000000000000000000000000000000000000800", data: "0x12345678" });
console.log(`inactive precompile 0x…0800 returndata: ${JSON.stringify(inactive.data ?? null)}`);

const T = "0x0000000000000000000000000000000000000000000000000000000000000001";
const F = "0x0000000000000000000000000000000000000000000000000000000000000000";
const pass = r1 === T && r2 === F && r3 === F && r4 === F && r5 === T;
console.log(pass ? "S3 TRACK B: PASS" : "S3 TRACK B: FAIL");
process.exit(pass ? 0 : 1);
