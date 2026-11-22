/**
 * pnpm canary:verify [--selftest] [--msg ...] [--dst ...]
 *  --selftest  RFC 9380 Appendix J.8.1 vectors (secp256k1_XMD:SHA-256_SSWU_RO_) must all match, or exit 1.
 *  default     also re-derive the real canary and compare with deployments/canary.json and with the address
 *              stored on-chain in CanaryRegistry (eth_call), if deployments/testnet.json exists.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import type { Address } from "viem";
import { REPO_ROOT } from "./lib/env.js";
import { REAL_CANARY, deriveCanary, hashToCurveXY } from "./lib/canary.js";
import { deploymentPath, readDeployment } from "./lib/deployments.js";
import { publicClient } from "./lib/evm.js";
import { registryAbi } from "./lib/pool.js";

const { values } = parseArgs({ options: { selftest: { type: "boolean" }, msg: { type: "string" }, dst: { type: "string" } } });
let ok = true;
const check = (label: string, pass: boolean, detail = "") => {
  ok &&= pass;
  console.log(`${pass ? "PASS" : "FAIL"}  ${label}${detail ? `  ${detail}` : ""}`);
};

const rfc = JSON.parse(readFileSync(resolve(REPO_ROOT, "scripts/vectors/rfc9380-j81.json"), "utf8")) as { dst: string; vectors: { msg: string; x: string; y: string }[] };
for (const v of rfc.vectors) {
  const p = hashToCurveXY(v.msg, rfc.dst);
  check(`RFC 9380 J.8.1 msg=${JSON.stringify(v.msg.length > 16 ? v.msg.slice(0, 8) + "…(" + v.msg.length + ")" : v.msg)}`, p.x === v.x && p.y === v.y);
}

if (!values.selftest) {
  const c = deriveCanary(values.msg ?? REAL_CANARY.msg, values.dst ?? REAL_CANARY.dst);
  console.log(`derived  ${c.address}  from msg=${JSON.stringify(c.msg)} dst=${JSON.stringify(c.dst)}`);
  const saved = JSON.parse(readFileSync(resolve(REPO_ROOT, "deployments/canary.json"), "utf8")) as { address: Address };
  check("matches deployments/canary.json", saved.address === c.address, saved.address);
  if (existsSync(deploymentPath())) {
    const d = readDeployment();
    const onchain = (await publicClient.readContract({ address: d.registry, abi: registryAbi(), functionName: "getCanary", args: [0n] })) as { addr: Address; phrase: string; dst: string; isTest: boolean };
    check(`matches CanaryRegistry ${d.registry} canary #0 (eth_call)`, onchain.addr === c.address, onchain.addr);
    check("on-chain phrase and DST match", onchain.phrase === c.msg && onchain.dst === c.dst, `${JSON.stringify(onchain.phrase)} / ${JSON.stringify(onchain.dst)}`);
    check("canary #0 is flagged as the real canary", onchain.isTest === false);
  } else console.log("(no deployments/testnet.json yet: on-chain comparison skipped)");
}
console.log(ok ? "verify-canary: ALL PASS" : "verify-canary: FAILED");
process.exit(ok ? 0 : 1);
