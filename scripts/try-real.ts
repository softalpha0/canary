/**
 * pnpm demo:try-real — shows the REAL canary cannot be killed: a random secp256k1 key signs canary 0's break
 * digest and we submit it via eth_call (simulation, no gas, no window). Expect InvalidBreakSignature.
 */
import { secp256k1 } from "@noble/curves/secp256k1.js";
import { BaseError, ContractFunctionRevertedError, bytesToHex, type Address, type Hex } from "viem";
import { privateKeyToAddress } from "viem/accounts";
import { signBreakDigest } from "./lib/break-sig.js";
import { readDeployment } from "./lib/deployments.js";
import { publicClient } from "./lib/evm.js";
import { registryAbi } from "./lib/pool.js";
import { loadAccount } from "./lib/qore.js";

const d = readDeployment();
const abi = registryAbi();
const reporter = (await loadAccount("reporter")).evm as Address;
const key = bytesToHex(secp256k1.utils.randomSecretKey()) as Hex;
const digest = (await publicClient.readContract({ address: d.registry, abi, functionName: "breakDigest", args: [0n, reporter] })) as Hex;
const { v, r, s } = await signBreakDigest(digest, key, privateKeyToAddress(key));
console.log(`Trying to kill the REAL canary #0 with a random key's signature over breakDigest(0, ${reporter})…`);
try {
  await publicClient.simulateContract({ address: d.registry, abi, functionName: "reportBreak", args: [0n, reporter, v, r, s], account: reporter });
  console.log("UNEXPECTED: the call would succeed");
  process.exit(1);
} catch (e) {
  const rev = e instanceof BaseError ? e.walk((x) => x instanceof ContractFunctionRevertedError) : null;
  const name = rev instanceof ContractFunctionRevertedError ? rev.data?.errorName : undefined;
  console.log(`Reverted: ${name ?? (e as Error).message.split("\n")[0]}`);
  console.log(name === "InvalidBreakSignature" ? "try-real: PASS (the real canary cannot be killed)" : "try-real: unexpected revert reason");
  process.exit(name === "InvalidBreakSignature" ? 0 : 1);
}
