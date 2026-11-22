/**
 * Serves the M0 browser spike page on http://localhost:5174 (MetaMask/QoreX do not inject into file://).
 * Fills in the spike digest and function selectors computed with viem, so the page needs no libraries.
 *   pnpm --filter scripts exec tsx spikes/browser/serve.ts
 */
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { keccak256, toBytes, toFunctionSelector } from "viem";

const here = dirname(fileURLToPath(import.meta.url));
export const S3A_DIGEST = keccak256(toBytes("Canary spike S3 track A"));
const html = readFileSync(resolve(here, "index.html"), "utf8")
  .replace("__DIGEST__", S3A_DIGEST)
  .replace("__SEL_VERIFY__", toFunctionSelector("pqcVerify(bytes,bytes,bytes)").slice(2))
  .replace("__SEL_KEYSTATUS__", toFunctionSelector("pqcKeyStatus(address)").slice(2));

const port = Number(process.env.PORT ?? 5174);
createServer((req, res) => {
  if (req.url === "/" || req.url === "/index.html") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" }).end(html);
  } else res.writeHead(404).end();
}).listen(port, "127.0.0.1", () => console.log(`Spike page: http://localhost:${port}  (digest ${S3A_DIGEST})`));
