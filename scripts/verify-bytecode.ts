/** pnpm verify:bytecode — compare every deployed contract's runtime code with the Foundry artifacts (immutables masked). */
import { readDeployment } from "./lib/deployments.js";
import { verifyBytecode } from "./lib/bytecode.js";

const d = readDeployment();
let ok = true;
const items: [string, `0x${string}`, string][] = [["CanaryRegistry", d.registry, "CanaryRegistry"], ...Object.entries(d.pools).map(([id, a]) => [`CoverPool #${id}`, a, "CoverPool"] as [string, `0x${string}`, string])];
for (const [label, address, name] of items) {
  const v = await verifyBytecode(address, `${name}.sol`, name);
  ok &&= v.match;
  console.log(`${v.match ? "MATCH   " : "MISMATCH"} ${label.padEnd(15)} ${address}  ${v.onchainBytes} bytes, ${v.immutables} immutable refs masked`);
}
console.log(ok ? "verify-bytecode: ALL MATCH" : "verify-bytecode: MISMATCH");
process.exit(ok ? 0 : 1);
