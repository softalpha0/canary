/**
 * Authorised CoverPool calls from scripts (Track B): read the digest from the contract's actionDigest view
 * (never rebuilt alone in JS; we also assert our JS builder agrees), sign with the owner's ML-DSA key,
 * send with gas = estimate × 1.25 (the chain charges at least 50% of the limit — SPIKES S2).
 */
import { encodeAbiParameters, keccak256, type Abi, type Address, type Hex } from "viem";
import { config } from "../config.js";
import type { AccountName } from "../config.js";
import { ACTIONS, actionDigest, type ActionName } from "./digest.js";
import { artifact, fees, publicClient, walletFor } from "./evm.js";
import { pqSignDigest } from "./pq.js";
import { loadAccount } from "./qore.js";

export const poolAbi = (): Abi => artifact("CoverPool").abi;
export const registryAbi = (): Abi => artifact("CanaryRegistry").abi;

export async function sendTx(from: AccountName, to: Address, abi: Abi, functionName: string, args: unknown[], value = 0n) {
  const a = await loadAccount(from);
  const est = await publicClient.estimateContractGas({ address: to, abi, functionName, args, value, account: a.evm as Address });
  const gas = (est * 125n) / 100n;
  const hash = await walletFor(a).writeContract({ address: to, abi, functionName, args, value, gas, ...(await fees()) });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`${functionName} reverted: ${hash}`);
  return { hash, receipt, gas, estimate: est };
}

export interface AuthorisedCall {
  pool: Address;
  signer: AccountName; // whose ML-DSA key signs (the owner / admin)
  submitter: AccountName; // who sends the EVM tx (pays gas; no authority)
  action: ActionName;
  owner: Address;
  params: { types: { type: string }[]; values: unknown[] };
  functionName: string;
  /** builds the call args given (deadline, sig) */
  args: (deadline: bigint, sig: Hex) => unknown[];
}

export async function authorised(c: AuthorisedCall) {
  const abi = poolAbi();
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 600);
  const ph = keccak256(encodeAbiParameters(c.params.types as never, c.params.values as never));
  const digest = (await publicClient.readContract({
    address: c.pool,
    abi,
    functionName: "actionDigest",
    args: [ACTIONS[c.action], c.owner, deadline, ph],
  })) as Hex;
  const nonce = (await publicClient.readContract({ address: c.pool, abi, functionName: "nonces", args: [c.owner] })) as bigint;
  const js = actionDigest({ chainId: BigInt(config.evmChainId), verifyingContract: c.pool, action: ACTIONS[c.action], owner: c.owner, nonce, deadline, paramsHash: ph });
  if (js !== digest) throw new Error(`JS digest ${js} != contract actionDigest ${digest}`);
  const sig = await pqSignDigest(c.signer, digest);
  const res = await sendTx(c.submitter, c.pool, abi, c.functionName, c.args(deadline, sig));
  return { ...res, digest, nonce, sig };
}
