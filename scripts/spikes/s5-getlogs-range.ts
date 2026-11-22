/** SPIKE S5: largest block range eth_getLogs accepts on the public RPC. */
import { createPublicClient, http } from "viem";
import { qoreTestnet } from "../config.js";

const client = createPublicClient({ chain: qoreTestnet, transport: http(undefined, { retryCount: 0, timeout: 30_000 }) });
const head = await client.getBlockNumber();
console.log(`head=${head}`);
async function tryRange(n: bigint) {
  const t = Date.now();
  try {
    const logs = await client.getLogs({ fromBlock: head - n + 1n, toBlock: head });
    console.log(`range ${n.toString().padStart(7)}: OK   ${logs.length} logs, ${Date.now() - t} ms`);
    return true;
  } catch (e) {
    console.log(`range ${n.toString().padStart(7)}: FAIL ${(e as Error).message.split("\n").find((l) => /details|message/i.test(l)) ?? (e as Error).message.split("\n")[0]}`);
    return false;
  }
}
for (const n of [100n, 1_000n, 5_000n, 10_000n, 50_000n, 100_000n]) await tryRange(n);
// binary search the boundary between the largest OK and smallest FAIL
let lo = 1n, hi = 200_000n;
if (await tryRange(hi)) { console.log(`>= ${hi} accepted`); process.exit(0); }
while (hi - lo > 1n) { const mid = (lo + hi) / 2n; (await tryRange(mid)) ? (lo = mid) : (hi = mid); }
console.log(`S5 RESULT: max eth_getLogs range = ${lo} blocks`);
