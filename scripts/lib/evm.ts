import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createPublicClient, createWalletClient, http, type Abi, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { qoreTestnet } from "../config.js";
import { REPO_ROOT } from "./env.js";
import type { UnifiedAccount } from "./qore.js";

export const publicClient = createPublicClient({ chain: qoreTestnet, transport: http() });

export function walletFor(a: UnifiedAccount) {
  return createWalletClient({ chain: qoreTestnet, transport: http(), account: privateKeyToAccount(a.privateKey as Hex) });
}

/** Load a Foundry artifact: contracts/out/<File>.sol/<Name>.json */
export function artifact(file: string, name = file.replace(/\.sol$/, "")) {
  const p = resolve(REPO_ROOT, "contracts", "out", file.endsWith(".sol") ? file : `${file}.sol`, `${name}.json`);
  const j = JSON.parse(readFileSync(p, "utf8")) as { abi: Abi; bytecode: { object: Hex }; deployedBytecode: { object: Hex } };
  return { abi: j.abi, bytecode: j.bytecode.object, deployedBytecode: j.deployedBytecode.object };
}

/** EIP-1559 fees with a floor of 0.1 uqor/gas (= 1e11 wei) per the network docs. */
export async function fees() {
  const f = await publicClient.estimateFeesPerGas();
  const floor = 100_000_000_000n;
  const maxPriorityFeePerGas = f.maxPriorityFeePerGas ?? 0n;
  const maxFeePerGas = f.maxFeePerGas < floor ? floor * 2n : f.maxFeePerGas;
  return { maxFeePerGas, maxPriorityFeePerGas };
}

/** Window budget consumed by a tx, in uqor: value + gas * maxFeePerGas, wei → uqor rounding up. */
export const windowCostUqor = (gas: bigint, maxFeePerGas: bigint, value = 0n) =>
  (value + gas * maxFeePerGas + 999_999_999_999n) / 1_000_000_000_000n;
