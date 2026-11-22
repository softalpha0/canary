/**
 * Checks the spike page's hand-written ABI encoding and bech32 decoding against the live precompile,
 * using a known-good Track B signature. Requires serve.ts running on :5174.
 */
import { createRequire } from "node:module";
import { mldsa } from "@qorechain/pqc";
import { bytesToHex, hexToBytes, type Hex } from "viem";
import { publicClient } from "../../lib/evm.js";
import { loadAccount } from "../../lib/qore.js";

const S3A_DIGEST = "0x8404311f59f0ac17137acf43cf0fa749412488e891cdb0bc48c9915252776ecc";
const require = createRequire(import.meta.url);
// Pre-installed global Playwright (not a repo dependency); minimal local typing.
interface Page { goto(u: string, o?: object): Promise<unknown>; evaluate(expr: string): Promise<unknown> }
const { chromium } = require("playwright") as { chromium: { launch(): Promise<{ newPage(): Promise<Page>; close(): Promise<void> }> } };

const a = await loadAccount("deployer");
const sig = mldsa.sign(a.pqc.secretKey, hexToBytes(S3A_DIGEST));
const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto("http://localhost:5174", { timeout: 15_000 });

// Encode inside the page by bare name (script-scope bindings), then eth_call from Node.
const enc = (pk: string, sg: string, d: string) =>
  page.evaluate(`"0x" + SEL_VERIFY + encVerifyBody(fromHex("${pk}"), fromHex("${sg}"), fromHex("${d}"))`) as Promise<Hex>;
const badDigest = ("0x" + (parseInt(S3A_DIGEST.slice(2, 4), 16) ^ 1).toString(16).padStart(2, "0") + S3A_DIGEST.slice(4)) as Hex;
const call = async (data: Hex) => (await publicClient.call({ to: "0x0000000000000000000000000000000000000a01", data })).data ?? "0x0";
const pkHex = bytesToHex(a.pqc.publicKey);
const sgHex = bytesToHex(sig);
const good = await call(await enc(pkHex, sgHex, S3A_DIGEST));
const bad = await call(await enc(pkHex, sgHex, badDigest));
const b32 = (await page.evaluate(`bech32ToHex("${a.cosmos}")`)) as string;
await browser.close();

console.log({ good, bad, bech32ToHex: b32, expected: a.evm.toLowerCase() });
const ok = BigInt(good) === 1n && BigInt(bad) === 0n && b32.toLowerCase() === a.evm.toLowerCase();
console.log(ok ? "page encoding self-check: PASS" : "page encoding self-check: FAIL");
process.exit(ok ? 0 : 1);
