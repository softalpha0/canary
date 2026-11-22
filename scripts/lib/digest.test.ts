import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import type { Address, Hex } from "viem";
import { ACTIONS, DOMAIN_TAG, actionDigest, paramsHash } from "./digest.js";
import { REPO_ROOT } from "./env.js";

const v = JSON.parse(readFileSync(resolve(REPO_ROOT, "contracts/test/vectors/digest.json"), "utf8")) as Record<string, string | number>;

describe("action digest matches the Foundry-exported vector", () => {
  it("domain tag and action constant", () => {
    expect(DOMAIN_TAG).toBe(v.domainTag);
    expect(ACTIONS.CLAIM_PAYOUT).toBe(v.action);
  });
  it("paramsHash(CLAIM_PAYOUT)", () => {
    expect(paramsHash.CLAIM_PAYOUT(BigInt(v.paramPolicyId!), v.paramRecipient as Address)).toBe(v.paramsHash);
  });
  it("digest", () => {
    expect(
      actionDigest({
        chainId: BigInt(v.chainId!),
        verifyingContract: v.verifyingContract as Address,
        action: v.action as Hex,
        owner: v.owner as Address,
        nonce: BigInt(v.nonce!),
        deadline: BigInt(v.deadline!),
        paramsHash: v.paramsHash as Hex,
      }),
    ).toBe(v.digest);
  });
});
