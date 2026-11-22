/**
 * Compare on-chain runtime code to a Foundry artifact's deployedBytecode, masking immutable references
 * (artifact.deployedBytecode.immutableReferences). There is no explorer verification on QoreChain (plan 05),
 * so this is how anyone checks the deployed contracts are exactly this source.
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { Address, Hex } from "viem";
import { REPO_ROOT } from "./env.js";
import { publicClient } from "./evm.js";

interface Artifact {
  deployedBytecode: { object: Hex; immutableReferences?: Record<string, { start: number; length: number }[]> };
}

export function loadArtifact(file: string, name: string): Artifact {
  return JSON.parse(readFileSync(resolve(REPO_ROOT, "contracts", "out", file, `${name}.json`), "utf8")) as Artifact;
}

export function maskImmutables(code: Hex, refs: Artifact["deployedBytecode"]["immutableReferences"] = {}): string {
  const b = code.slice(2).toLowerCase().split("");
  for (const list of Object.values(refs)) {
    for (const { start, length } of list) for (let i = start * 2; i < (start + length) * 2; i++) b[i] = "0";
  }
  return b.join("");
}

export async function verifyBytecode(address: Address, file: string, name: string) {
  const art = loadArtifact(file, name);
  const onchain = (await publicClient.getCode({ address })) ?? "0x";
  const refs = art.deployedBytecode.immutableReferences ?? {};
  const a = maskImmutables(onchain, refs);
  const b = maskImmutables(art.deployedBytecode.object, refs);
  const immutables = Object.values(refs).reduce((n, l) => n + l.length, 0); // number of immutable references masked
  return { match: a === b && a.length > 0, onchainBytes: (onchain.length - 2) / 2, artifactBytes: (art.deployedBytecode.object.length - 2) / 2, immutables };
}
