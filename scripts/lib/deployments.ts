import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import type { Address, Hex } from "viem";
import { REPO_ROOT } from "./env.js";

export interface PoolInfo {
  address: Address;
  canaryId: number;
  label: string;
  tx: Hex;
  block: string;
  config: Record<string, string | number>;
}
export interface TestnetDeployment {
  network: string;
  cosmosChainId: string;
  evmChainId: number;
  deployedAt: string;
  deployer: Address;
  msgMode: number;
  deployBlock: string;
  registry: Address;
  registryTx: Hex;
  pools: Record<string, Address>; // canaryId → pool
  poolInfo: Record<string, PoolInfo>;
  canaries: { id: number; address: Address; isTest: boolean; label: string; msg: string; dst: string }[];
}

export const deploymentPath = (name = process.env.DEPLOYMENT_FILE ?? "testnet.json") =>
  resolve(REPO_ROOT, "deployments", name);

export function readDeployment(): TestnetDeployment {
  const p = deploymentPath();
  if (!existsSync(p)) throw new Error(`No ${p}. Deploy first: pnpm deploy:testnet`);
  return JSON.parse(readFileSync(p, "utf8")) as TestnetDeployment;
}

export function writeDeployment(d: TestnetDeployment) {
  mkdirSync(resolve(REPO_ROOT, "deployments"), { recursive: true });
  writeFileSync(deploymentPath(), JSON.stringify(d, null, 2) + "\n");
}
