/**
 * Run `forge script` as a demo account without ever printing its key: the key is derived from the
 * account mnemonic in .env and handed to forge only through the child's PRIVATE_KEY env var
 * (scripts read it with vm.envUint("PRIVATE_KEY")).
 *
 *   tsx forge-script.ts --account deployer -- script/Foo.s.sol:Foo --broadcast [forge flags...]
 */
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { ACCOUNT_NAMES, config, type AccountName } from "./config.js";
import { REPO_ROOT } from "./lib/env.js";
import { loadAccount } from "./lib/qore.js";

const argv = process.argv.slice(2);
const sep = argv.indexOf("--");
const name = (argv[argv.indexOf("--account") + 1] ?? "deployer") as AccountName;
if (sep < 0 || !ACCOUNT_NAMES.includes(name)) {
  console.error("Usage: tsx forge-script.ts --account <name> -- <forge script args>");
  process.exit(1);
}
const a = await loadAccount(name);
const forge = process.env.FORGE_BIN ?? "forge";
const r = spawnSync(forge, ["script", ...argv.slice(sep + 1), "--rpc-url", config.evmRpc], {
  cwd: resolve(REPO_ROOT, "contracts"),
  stdio: "inherit",
  env: { ...process.env, PRIVATE_KEY: a.privateKey },
});
process.exit(r.status ?? 1);
