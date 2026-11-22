/**
 * pnpm demo:kill --canary 1 --reporter <0x reporter>   (the demo trigger, plan 04)
 * Reads breakDigest(id, reporter) from the registry (never rebuilt off-chain), signs it RAW with
 * TEST_CANARY_PRIVATE_KEY (no Ethereum message prefix), and submits reportBreak from the `reporter` account
 * (needs a scoped window including the registry). Refuses canary 0, the real canary.
 */
import { parseArgs } from "node:util";
import { getAddress, parseEventLogs, type Address, type Hex } from "viem";
import { requireEnv } from "./lib/env.js";
import { signBreakDigest } from "./lib/break-sig.js";
import { readDeployment } from "./lib/deployments.js";
import { publicClient } from "./lib/evm.js";
import { registryAbi, sendTx } from "./lib/pool.js";
import { loadAccount } from "./lib/qore.js";

const { values } = parseArgs({ options: { canary: { type: "string", default: "1" }, reporter: { type: "string" } } });
const id = BigInt(values.canary ?? "1");
if (id === 0n) {
  console.error("Refusing: canary 0 is the REAL canary. Nobody can kill it without breaking ECDSA (try pnpm demo:try-real).");
  process.exit(1);
}
const d = readDeployment();
const abi = registryAbi();
const reporter = getAddress(values.reporter ?? (await loadAccount("reporter")).evm);
const c = (await publicClient.readContract({ address: d.registry, abi, functionName: "getCanary", args: [id] })) as { addr: Address; isTest: boolean; deadAt: bigint };
if (!c.isTest) throw new Error(`Canary ${id} is not a test canary.`);
if (c.deadAt !== 0n) throw new Error(`Canary ${id} is already dead (deadAt ${c.deadAt}).`);
const digest = (await publicClient.readContract({ address: d.registry, abi, functionName: "breakDigest", args: [id, reporter] })) as Hex;
const { v, r, s } = await signBreakDigest(digest, requireEnv("TEST_CANARY_PRIVATE_KEY") as Hex, c.addr);
console.log(`breakDigest(${id}, ${reporter}) = ${digest}\nsigned by test canary ${c.addr}: v=${v} r=${r} s=${s}`);
const { hash, receipt } = await sendTx("reporter", d.registry, abi, "reportBreak", [id, reporter, v, r, s]);
const ev = parseEventLogs({ abi, logs: receipt.logs, eventName: "CanaryDied" })[0];
console.log(`reportBreak tx ${hash} block ${receipt.blockNumber}`);
console.log(`CanaryDied ${JSON.stringify(ev?.args, (_, x) => (typeof x === "bigint" ? x.toString() : x))}`);
