/**
 * pnpm canary:gen-test [--force]
 * Generates a normal random secp256k1 keypair for the TEST canary (plan 04). The private key goes to .env as
 * TEST_CANARY_PRIVATE_KEY (git-ignored, never printed); the address to deployments/test-canary.json.
 */
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { secp256k1 } from "@noble/curves/secp256k1.js";
import { bytesToHex } from "viem";
import { privateKeyToAddress } from "viem/accounts";
import { ENV_PATH, REPO_ROOT } from "./lib/env.js";

const force = process.argv.includes("--force");
const env = existsSync(ENV_PATH) ? readFileSync(ENV_PATH, "utf8") : "";
if (/^TEST_CANARY_PRIVATE_KEY=\S+/m.test(env) && !force) {
  console.error("TEST_CANARY_PRIVATE_KEY already set in .env. Refusing to overwrite (pass --force to replace it).");
  process.exit(1);
}
const key = bytesToHex(secp256k1.utils.randomSecretKey());
const address = privateKeyToAddress(key);
const line = `TEST_CANARY_PRIVATE_KEY=${key}`;
const next = /^TEST_CANARY_PRIVATE_KEY=.*$/m.test(env)
  ? env.replace(/^TEST_CANARY_PRIVATE_KEY=.*$/m, line)
  : env.replace(/\n*$/, "\n") + line + "\n";
writeFileSync(ENV_PATH, next, { mode: 0o600 });
mkdirSync(resolve(REPO_ROOT, "deployments"), { recursive: true });
writeFileSync(
  resolve(REPO_ROOT, "deployments", "test-canary.json"),
  JSON.stringify({ label: "TEST canary", address, note: "Key held by the team for demos (in .env, never committed)." }, null, 2) + "\n",
);
console.log(`Test canary address ${address}\nPrivate key written to .env (TEST_CANARY_PRIVATE_KEY). Address → deployments/test-canary.json`);
