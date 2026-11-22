/**
 * pnpm deploy:testnet [--dry-run] [--force]
 *
 * Deploys CanaryRegistry (real canary #0 + test canary #1) and two CoverPools (one per canary) from `deployer`
 * with viem + Foundry artifacts (deploy route decided in SPIKES S2 / DECISIONS D-007), in ONE run:
 *   1. open an UNSCOPED EVM window on deployer (contract creation is refused under allowedTargets)
 *   2. deploy registry, real pool, test pool (gas = eth_estimateGas × 1.25)
 *   3. check every contract's runtime code against its artifact (immutables masked)
 *   4. write deployments/testnet.json
 * --dry-run: run against EVM_RPC_URL (e.g. a local anvil fork with precompile mocks) without opening a window.
 * Refuses to overwrite an existing deployment file unless --force.
 */
import { existsSync } from "node:fs";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { getAddress, type Address, type Hex } from "viem";
import { config } from "./config.js";
import { REPO_ROOT } from "./lib/env.js";
import { artifact, fees, publicClient, walletFor, windowCostUqor } from "./lib/evm.js";
import { verifyBytecode } from "./lib/bytecode.js";
import { deploymentPath, writeDeployment, type TestnetDeployment } from "./lib/deployments.js";
import { REAL_CANARY, deriveCanary } from "./lib/canary.js";
import { loadAccount, openWindow } from "./lib/qore.js";

const dryRun = process.argv.includes("--dry-run");
const force = process.argv.includes("--force");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const QOR = 10n ** 18n;

if (existsSync(deploymentPath()) && !force) {
  console.error(`${deploymentPath()} exists. Refusing to redeploy over it (pass --force, and keep the old addresses in DEPLOYMENTS.md).`);
  process.exit(1);
}

// ---- canaries
const real = deriveCanary(REAL_CANARY.msg, REAL_CANARY.dst);
const savedReal = JSON.parse(readFileSync(resolve(REPO_ROOT, "deployments", "canary.json"), "utf8"));
if (savedReal.address !== real.address) throw new Error("deployments/canary.json does not match a fresh derivation");
const testCanary = JSON.parse(readFileSync(resolve(REPO_ROOT, "deployments", "test-canary.json"), "utf8")) as { address: Address };
const canaries = [
  { addr: real.address, isTest: false, deadAt: 0n, reporter: "0x0000000000000000000000000000000000000000", label: "Canary #1 (secp256k1, RFC 9380)", phrase: real.msg, dst: real.dst },
  { addr: getAddress(testCanary.address), isTest: true, deadAt: 0n, reporter: "0x0000000000000000000000000000000000000000", label: "TEST canary (demo key held by the team)", phrase: "", dst: "" },
] as const;

// ---- pool parameters (plan 03 table). msgMode RAW (DECISIONS D-001).
const deployer = await loadAccount("deployer");
const baseConfig = { admin: deployer.evm as Address, msgMode: 0, minDeposit: QOR / 100n, maxRateBps: 5000n, bountyBps: 100n };
const realPool = { ...baseConfig, canaryId: 0n, minDuration: 86400n, maxDuration: 365n * 86400n, cooldown: 3n * 86400n, claimWindow: 30n * 86400n, bountyCap: 10n * QOR, premiumRateBps: 100n };
const testPool = { ...baseConfig, canaryId: 1n, minDuration: 60n, maxDuration: 30n * 86400n, cooldown: 120n, claimWindow: 3600n, bountyCap: 1n * QOR, premiumRateBps: 2000n };

const wallet = walletFor(deployer);
const f = await fees();
console.log(`${dryRun ? "[DRY RUN] " : ""}deployer ${deployer.evm} on chain ${await publicClient.getChainId()} via ${config.evmRpc}`);
console.log(`real canary ${real.address}  test canary ${testCanary.address}`);

async function deploy(file: string, args: unknown[]) {
  const art = artifact(file);
  const est = await publicClient.estimateGas({ account: deployer.evm as Address, data: (await import("viem")).encodeDeployData({ abi: art.abi, bytecode: art.bytecode, args }) });
  const gas = (est * 125n) / 100n;
  const hash = await wallet.deployContract({ abi: art.abi, bytecode: art.bytecode, args, gas, ...f });
  const r = await publicClient.waitForTransactionReceipt({ hash });
  if (r.status !== "success" || !r.contractAddress) throw new Error(`${file} deploy failed: ${hash}`);
  console.log(`${file.padEnd(15)} ${r.contractAddress}  tx ${hash}  block ${r.blockNumber}  gas ${r.gasUsed}/${gas} (est ${est})`);
  return { address: getAddress(r.contractAddress), hash, block: r.blockNumber };
}

// ---- 1. unscoped deploy window (budget: 3 deploys at up to 6M gas each)
if (!dryRun) {
  const w = await openWindow(deployer, { blocks: 1200, maxTxs: 4, maxValueUqor: windowCostUqor(18_000_000n, f.maxFeePerGas) });
  console.log(`unscoped deploy window: tx ${w.transactionHash} height ${w.height}`);
  await sleep(10_000);
}

// ---- 2. deploy
const reg = await deploy("CanaryRegistry", [canaries]);
const p0 = await deploy("CoverPool", [{ registry: reg.address, ...realPool }]);
const p1 = await deploy("CoverPool", [{ registry: reg.address, ...testPool }]);

// ---- 3. runtime code checks
for (const [name, file, c] of [["CanaryRegistry", "CanaryRegistry.sol", reg], ["CoverPool #0", "CoverPool.sol", p0], ["CoverPool #1", "CoverPool.sol", p1]] as const) {
  const v = await verifyBytecode(c.address, file, file.replace(".sol", ""));
  console.log(`bytecode ${name.padEnd(15)} ${v.match ? "MATCH" : "MISMATCH"} (${v.onchainBytes} bytes, ${v.immutables} immutable refs masked)`);
  if (!v.match) throw new Error(`Bytecode mismatch for ${name}`);
}

// ---- 4. record
const str = (o: Record<string, unknown>) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, typeof v === "bigint" ? v.toString() : (v as string | number)]));
const d: TestnetDeployment = {
  network: dryRun ? "DRY-RUN (local fork)" : "QoreChain testnet",
  cosmosChainId: config.cosmosChainId,
  evmChainId: config.evmChainId,
  deployedAt: new Date().toISOString(),
  deployer: deployer.evm as Address,
  msgMode: 0,
  deployBlock: reg.block.toString(),
  registry: reg.address,
  registryTx: reg.hash as Hex,
  pools: { "0": p0.address, "1": p1.address },
  poolInfo: {
    "0": { address: p0.address, canaryId: 0, label: "Real canary pool", tx: p0.hash as Hex, block: p0.block.toString(), config: str(realPool) },
    "1": { address: p1.address, canaryId: 1, label: "Test canary pool", tx: p1.hash as Hex, block: p1.block.toString(), config: str(testPool) },
  },
  canaries: canaries.map((c, id) => ({ id, address: c.addr, isTest: c.isTest, label: c.label, msg: c.phrase, dst: c.dst })),
};
writeDeployment(d);
console.log(`→ ${deploymentPath()}`);
