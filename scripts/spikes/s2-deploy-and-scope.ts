/**
 * SPIKE S2: (a) which deploy route works — this is the viem route (Foundry artifacts, explicit gas);
 * the forge-script route is tried separately with the command recorded in docs/SPIKES.md.
 * (b) does a scoped window admit calls to listed targets and refuse others (expected pqc code 27)?
 * Also measures real gas of an in-contract pqcVerify + pqcKeyStatus (PQProbe.probe).
 *
 * Prereqs: deployer funded and PQC-registered (S1). Run: forge build && tsx spikes/s2-deploy-and-scope.ts
 * Writes deployments/spikes.json.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { mldsa } from "@qorechain/pqc";
import { classifyEvmWindowRejection } from "@qorechain/sdk";
import { bytesToHex, keccak256, parseEventLogs, toBytes } from "viem";
import { REPO_ROOT } from "../lib/env.js";
import { artifact, fees, publicClient, walletFor, windowCostUqor } from "../lib/evm.js";
import { loadAccount, openWindow, windowStatus } from "../lib/qore.js";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const deployer = await loadAccount("deployer");
const wallet = walletFor(deployer);
const f = await fees();
console.log(`fees: maxFeePerGas=${f.maxFeePerGas} maxPriorityFeePerGas=${f.maxPriorityFeePerGas}`);

// ---- (a) unscoped window for deploys
const DEPLOY_GAS = 1_500_000n;
const w0 = await openWindow(deployer, { blocks: 600, maxTxs: 4, maxValueUqor: windowCostUqor(DEPLOY_GAS * 3n, f.maxFeePerGas) });
console.log(`unscoped window: tx ${w0.transactionHash} height ${w0.height}`);
await sleep(10_000);

async function deploy(file: string) {
  const art = artifact(file);
  const hash = await wallet.deployContract({ abi: art.abi, bytecode: art.bytecode, gas: DEPLOY_GAS, ...f });
  const rcpt = await publicClient.waitForTransactionReceipt({ hash });
  if (rcpt.status !== "success" || !rcpt.contractAddress) throw new Error(`${file} deploy failed: ${hash}`);
  const code = await publicClient.getCode({ address: rcpt.contractAddress });
  const codeOk = code?.toLowerCase() === art.deployedBytecode.toLowerCase();
  console.log(`${file}: ${rcpt.contractAddress} tx ${hash} block ${rcpt.blockNumber} gasUsed ${rcpt.gasUsed} runtimeCodeMatches=${codeOk}`);
  return { address: rcpt.contractAddress, hash, block: rcpt.blockNumber, gasUsed: rcpt.gasUsed, codeOk, abi: art.abi };
}
const counter = await deploy("Counter");
const probe = await deploy("PQProbe");

// ---- (b) scoped window: only PQProbe is a target
const CALL_GAS = 1_000_000n;
const w1 = await openWindow(deployer, {
  blocks: 600,
  maxTxs: 4,
  maxValueUqor: windowCostUqor(CALL_GAS * 3n, f.maxFeePerGas),
  allowedTargets: [probe.address],
});
console.log(`scoped window (targets=[PQProbe]): tx ${w1.transactionHash} height ${w1.height}`);
await sleep(10_000);
const ws = await windowStatus(deployer.cosmos);
console.log(`window: live=${ws.live} targets=${ws.allowedTargets.join(",")} remainingTxs=${ws.remainingTxs}`);

// allowed: PQProbe.probe(sig, digest) with a real ML-DSA-87 signature by deployer's registered key
const digest = toBytes(keccak256(toBytes("Canary spike S2 probe")));
const sig = mldsa.sign(deployer.pqc.secretKey, digest);
const allowedHash = await wallet.writeContract({
  address: probe.address,
  abi: probe.abi,
  functionName: "probe",
  args: [bytesToHex(sig), bytesToHex(digest)],
  gas: CALL_GAS,
  ...f,
});
const allowed = await publicClient.waitForTransactionReceipt({ hash: allowedHash });
const events = parseEventLogs({ abi: probe.abi, logs: allowed.logs });
console.log(`ALLOWED PQProbe.probe: tx ${allowedHash} status ${allowed.status} gasUsed ${allowed.gasUsed}`);
for (const e of events) console.log(`  event ${e.eventName} ${JSON.stringify(e.args, (_, v) => (typeof v === "bigint" ? v.toString() : v))}`);

// refused: Counter.increment() is not a target
let refused: { message: string; classified: string } | undefined;
try {
  const h = await wallet.writeContract({ address: counter.address, abi: counter.abi, functionName: "increment", gas: 100_000n, ...f });
  const r = await publicClient.waitForTransactionReceipt({ hash: h });
  console.log(`UNEXPECTED: Counter.increment admitted: ${h} status ${r.status}`);
} catch (e) {
  const err = e as Error & { details?: string; shortMessage?: string };
  refused = { message: err.details ?? err.shortMessage ?? err.message, classified: String(classifyEvmWindowRejection(err)) };
  console.log(`REFUSED Counter.increment (non-target): ${refused.message}  classify=${refused.classified}`);
}
const wsAfter = await windowStatus(deployer.cosmos);
console.log(`window after: usedTxs=${wsAfter.usedTxs} remainingTxs=${wsAfter.remainingTxs} usedValue=${wsAfter.usedValue}uqor`);

mkdirSync(resolve(REPO_ROOT, "deployments"), { recursive: true });
writeFileSync(
  resolve(REPO_ROOT, "deployments", "spikes.json"),
  JSON.stringify(
    {
      network: "qorechain-diana/9800",
      date: new Date().toISOString(),
      counter: { address: counter.address, tx: counter.hash, block: counter.block.toString() },
      pqProbe: { address: probe.address, tx: probe.hash, block: probe.block.toString() },
      windows: { unscoped: w0.transactionHash, scoped: w1.transactionHash },
      allowedCall: { tx: allowedHash, gasUsed: allowed.gasUsed.toString(), status: allowed.status },
      refusedCall: refused ?? null,
    },
    null,
    2,
  ) + "\n",
);
const pass = counter.codeOk && probe.codeOk && allowed.status === "success" && refused !== undefined;
console.log(pass ? "S2: PASS" : "S2: FAIL");
process.exit(pass ? 0 : 1);
