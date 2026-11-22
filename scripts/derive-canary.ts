/**
 * pnpm canary:derive [--msg "QoreChain Canary 2026 #1"] [--dst "CANARY-V1-QORECHAIN_XMD:SHA-256_SSWU_RO_"]
 * Prints the canary point, uncompressed pubkey, EVM and qor1 address; writes deployments/canary.json.
 */
import { writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { REPO_ROOT } from "./lib/env.js";
import { REAL_CANARY, deriveCanary } from "./lib/canary.js";

const { values } = parseArgs({ options: { msg: { type: "string" }, dst: { type: "string" }, "no-write": { type: "boolean" } } });
const c = deriveCanary(values.msg ?? REAL_CANARY.msg, values.dst ?? REAL_CANARY.dst);
console.log(
  [
    `suite    secp256k1_XMD:SHA-256_SSWU_RO_ (RFC 9380 hash_to_curve)`,
    `msg      ${JSON.stringify(c.msg)}`,
    `dst      ${JSON.stringify(c.dst)}`,
    `X        ${c.x}`,
    `Y        ${c.y}`,
    `pubkey   ${c.pubkey}`,
    `address  ${c.address}`,
    `qor1     ${c.qor}`,
  ].join("\n"),
);
if (!values["no-write"]) {
  mkdirSync(resolve(REPO_ROOT, "deployments"), { recursive: true });
  writeFileSync(resolve(REPO_ROOT, "deployments", "canary.json"), JSON.stringify(c, null, 2) + "\n");
  console.log("→ deployments/canary.json");
}
