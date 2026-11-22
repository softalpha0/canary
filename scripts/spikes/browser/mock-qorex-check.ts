/**
 * Tests the S3 Track A handler end to end with a MOCK QoreX that returns the response shape seen from
 * the real extension ({signatureType, classical, pq, pub_key, signature}) with a real ML-DSA-87 sig over
 * prefix‖data in pq. Expect "prefix ‖ data" → TRUE. Requires serve.ts on :5174; uses global Playwright.
 */
// @ts-nocheck — test harness around the untyped global Playwright
import { createRequire } from "node:module";
import { mldsa } from "@qorechain/pqc";
import { loadAccount } from "../../lib/qore.js";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const a = await loadAccount("deployer");
const D = "0x8404311f59f0ac17137acf43cf0fa749412488e891cdb0bc48c9915252776ecc";
const prefix = Buffer.from("qorechain-msg-v1|qorechain-diana|");
const sign = (data: Buffer) => Buffer.from(mldsa.sign(a.pqc.secretKey, Buffer.concat([prefix, data]))).toString("base64");
const sigs = { s0x: sign(Buffer.from(D)), shex: sign(Buffer.from(D.slice(2))), raw: sign(Buffer.from(D.slice(2), "hex")) };
const pkB64 = Buffer.from(a.pqc.publicKey).toString("base64");
const browser = await chromium.launch(); const page = await browser.newPage();
// Injected as a string: esbuild-transpiled functions reference a __name helper that doesn't exist in the page.
await page.addInitScript(`window.qorex = { native: {
  capabilities: ["signArbitrary"], enable: async () => {}, getKey: async () => ({ bech32Address: ${JSON.stringify(a.cosmos)} }),
  signArbitrary: async (_c, _a, data) => {
    const sigs = ${JSON.stringify(sigs)};
    const pq = typeof data === "string" ? (data.startsWith("0x") ? sigs.s0x : sigs.shex) : sigs.raw;
    return { signatureType: "hybrid", classical: { signature: "AAAA" }, pq: { signature: pq, pub_key: ${JSON.stringify(pkB64)} }, pub_key: { type: "x", value: "AAAA" }, signature: btoa("x".repeat(64)) };
  } } };`);
// route RPC calls from the page through Node (headless browser has no proxy)
await page.route("https://evm-testnet.qore.host/**", async (r: any) => {
  const res = await fetch("https://evm-testnet.qore.host", { method: "POST", headers: { "content-type": "application/json" }, body: r.request().postData() });
  await r.fulfill({ status: 200, contentType: "application/json", body: await res.text() });
});
await page.goto("http://localhost:5174");
await page.click("#qx-connect"); await page.waitForTimeout(3000);
page.on("console", (m) => console.log("[page console]", m.text())); page.on("pageerror", (e) => console.log("[page error]", e.message));
console.log("after connect:", await page.textContent("#log"));
await page.click("#qx-run"); await page.waitForFunction(() => document.getElementById("log")!.textContent!.includes("RESULT"), null, { timeout: 90000 }).catch(() => console.log("TIMEOUT"));
console.log(await page.textContent("#log")); await browser.close();
