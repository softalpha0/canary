/**
 * EVM authorisation window helper (docs/plan/05_QORECHAIN_INTEGRATION.md).
 *
 *   pnpm window status       --account <name>
 *   pnpm window open-scoped  --account <name> [--targets 0xA,0xB] [--blocks 17280] [--txs 100] [--max-value-qor 50]
 *   pnpm window open-deploy  --account deployer [--blocks 3000] [--txs 20] [--max-value-qor 10]
 *   pnpm window close        --account <name>
 *
 * open-scoped defaults its targets to Canary's registry and pools from deployments/testnet.json.
 * open-deploy opens an UNSCOPED window: contract creation is refused under allowedTargets.
 * Uses @qorechain/sdk (openEvmWindowMsg / closeEvmWindowMsg / fetchEvmWindow), hybrid-signed.
 * CLI fallback (equivalent): qorechaind tx pqc open-evm-window <blocks> <max-txs> <max-value> --allowed-targets ...
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { ACCOUNT_NAMES, type AccountName } from "./config.js";
import { REPO_ROOT } from "./lib/env.js";
import { closeWindow, fmtQor, loadAccount, openWindow, windowStatus } from "./lib/qore.js";

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: {
    account: { type: "string", default: "deployer" },
    targets: { type: "string" },
    blocks: { type: "string" },
    txs: { type: "string" },
    "max-value-qor": { type: "string" },
  },
});

const name = values.account as AccountName;
if (!ACCOUNT_NAMES.includes(name)) throw new Error(`--account must be one of ${ACCOUNT_NAMES.join(", ")}`);

function canaryTargets(): string[] {
  const p = resolve(REPO_ROOT, "deployments", "testnet.json");
  if (!existsSync(p)) return [];
  const d = JSON.parse(readFileSync(p, "utf8")) as { registry?: string; pools?: Record<string, string> };
  return [d.registry, ...Object.values(d.pools ?? {})].filter((x): x is string => typeof x === "string");
}

const qorToUqor = (q: string) => BigInt(Math.round(Number(q) * 1e6));

async function status() {
  const a = await loadAccount(name);
  const w = await windowStatus(a.cosmos);
  if (!w.found) {
    console.log(`${name} ${a.cosmos}: no window`);
    return;
  }
  console.log(
    [
      `${name} ${a.cosmos} (${a.evm})`,
      `  live:        ${w.live}`,
      `  blocks:      opened ${w.openedHeight}, expires ${w.expiryHeight} (${w.remainingBlocks} left)`,
      `  txs:         ${w.usedTxs}/${w.maxTxs} used (${w.remainingTxs} left)`,
      `  value:       ${fmtQor(w.usedValue)} / ${fmtQor(w.maxValue)} used (${fmtQor(w.remainingValue)} left)`,
      `  scope:       ${w.nativeOnly ? "native-only" : w.allowedTargets.length ? `targets ${w.allowedTargets.join(", ")}` : "UNSCOPED (any target)"}`,
    ].join("\n"),
  );
}

async function open(scoped: boolean) {
  const a = await loadAccount(name);
  const targets = scoped ? (values.targets ? values.targets.split(",").map((s) => s.trim()) : canaryTargets()) : [];
  if (scoped && targets.length === 0) {
    throw new Error("No targets: pass --targets 0xA,0xB or deploy first so deployments/testnet.json exists.");
  }
  const p = {
    blocks: Number(values.blocks ?? (scoped ? 17280 : 3000)),
    maxTxs: Number(values.txs ?? (scoped ? 100 : 20)),
    maxValueUqor: qorToUqor(values["max-value-qor"] ?? (scoped ? "50" : "10")),
    allowedTargets: targets,
  };
  const res = await openWindow(a, p);
  console.log(
    `${scoped ? "Scoped" : "UNSCOPED deploy"} window opened for ${name} ${a.cosmos}\n` +
      `  tx ${res.transactionHash} height ${res.height}\n` +
      `  blocks=${p.blocks} maxTxs=${p.maxTxs} maxValue=${fmtQor(p.maxValueUqor)} targets=${targets.length ? targets.join(",") : "any"}\n` +
      `  Opening advanced the account nonce: wait ~10 s, then read the nonce before sending EVM txs.`,
  );
}

async function close() {
  const a = await loadAccount(name);
  const res = await closeWindow(a);
  console.log(`Window closed for ${name}: tx ${res.transactionHash} height ${res.height}`);
}

const cmds: Record<string, () => Promise<void>> = {
  status,
  "open-scoped": () => open(true),
  "open-deploy": () => open(false),
  close,
};
const run = cmds[positionals[0] ?? ""];
if (!run) {
  console.error("Usage: pnpm window <status|open-scoped|open-deploy|close> --account <name> [...]");
  process.exit(1);
}
run().catch((e: Error) => {
  console.error(`Error: ${e.message}`);
  process.exit(1);
});
