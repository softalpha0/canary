/** SPIKE S4: parse the receipt of the MetaMask-sent tx with viem.  tsx spikes/s4-receipt.ts <txHash> */
import { parseEventLogs, type Hex } from "viem";
import { artifact, publicClient } from "../lib/evm.js";

const hash = process.argv[2] as Hex | undefined;
if (!hash || !/^0x[0-9a-fA-F]{64}$/.test(hash)) throw new Error("Usage: tsx spikes/s4-receipt.ts <0x txHash>");
const [tx, rcpt] = await Promise.all([publicClient.getTransaction({ hash }), publicClient.waitForTransactionReceipt({ hash })]);
console.log(`tx ${hash}: from ${tx.from} to ${tx.to} type ${tx.type} chainId ${tx.chainId} nonce ${tx.nonce}`);
console.log(`receipt: status ${rcpt.status} block ${rcpt.blockNumber} gasUsed ${rcpt.gasUsed} effectiveGasPrice ${rcpt.effectiveGasPrice}`);
const extra = Object.keys(rcpt).filter((k) => !["blockHash","blockNumber","contractAddress","cumulativeGasUsed","effectiveGasPrice","from","gasUsed","logs","logsBloom","status","to","transactionHash","transactionIndex","type","blobGasPrice","blobGasUsed","root"].includes(k));
console.log(`non-standard receipt fields: ${extra.length ? extra.join(", ") : "none"}`);
for (const e of parseEventLogs({ abi: artifact("Counter").abi, logs: rcpt.logs }))
  console.log(`event ${e.eventName} ${JSON.stringify(e.args, (_, v) => (typeof v === "bigint" ? v.toString() : v))}`);
console.log(rcpt.status === "success" && tx.chainId === 9800 ? "S4: PASS" : "S4: FAIL");
