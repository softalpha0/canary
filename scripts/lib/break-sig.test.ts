import { describe, expect, it } from "vitest";
import { keccak256, toBytes } from "viem";
import { privateKeyToAddress } from "viem/accounts";
import { signBreakDigest } from "./break-sig.js";

describe("signBreakDigest", () => {
  const key = "0x00000000000000000000000000000000000000000000000000000000000c0ffe" as const;
  const addr = privateKeyToAddress(key);
  it("produces a raw ECDSA signature that recovers to the key's address", async () => {
    const d = keccak256(toBytes("break"));
    const { v, r, s } = await signBreakDigest(d, key, addr);
    expect([27, 28]).toContain(v);
    expect(r).toMatch(/^0x[0-9a-f]{64}$/);
    expect(s).toMatch(/^0x[0-9a-f]{64}$/);
  });
  it("refuses when the key is not the expected canary", async () => {
    await expect(signBreakDigest(keccak256(toBytes("x")), key, "0x000000000000000000000000000000000000dEaD")).rejects.toThrow(/Self-check failed/);
  });
});
