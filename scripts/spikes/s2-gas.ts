/** S2 follow-up: real gas needs (eth_estimateGas) vs the 50%-of-limit charging seen in S2 receipts. */
import { mldsa } from "@qorechain/pqc";
import { bytesToHex, encodeFunctionData, keccak256, toBytes, type Hex } from "viem";
import { artifact, publicClient } from "../lib/evm.js";
import { loadAccount } from "../lib/qore.js";
import spikes from "../../deployments/spikes.json" with { type: "json" };

const d = await loadAccount("deployer");
const digest = toBytes(keccak256(toBytes("Canary spike S2 gas")));
const sig = mldsa.sign(d.pqc.secretKey, digest);
const probe = artifact("PQProbe"), counter = artifact("Counter");
const est = async (label: string, args: Parameters<typeof publicClient.estimateGas>[0]) =>
  console.log(label.padEnd(28), (await publicClient.estimateGas(args)).toString());
await est("deploy Counter", { account: d.evm as Hex, data: counter.bytecode });
await est("deploy PQProbe", { account: d.evm as Hex, data: probe.bytecode });
await est("PQProbe.probe (PQ-auth'd)", { account: d.evm as Hex, to: spikes.pqProbe.address as Hex,
  data: encodeFunctionData({ abi: probe.abi, functionName: "probe", args: [bytesToHex(sig), bytesToHex(digest)] }) });
for (const h of [spikes.counter.tx, spikes.pqProbe.tx, spikes.allowedCall.tx] as Hex[]) {
  const [t, r] = await Promise.all([publicClient.getTransaction({ hash: h }), publicClient.getTransactionReceipt({ hash: h })]);
  console.log(`${h.slice(0, 12)}… gasLimit ${t.gas} gasUsed ${r.gasUsed} ratio ${(Number(r.gasUsed) / Number(t.gas)).toFixed(3)}`);
}
