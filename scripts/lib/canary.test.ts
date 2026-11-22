import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { REAL_CANARY, deriveCanary, hashToCurveXY } from "./canary.js";
import { REPO_ROOT } from "./env.js";

const rfc = JSON.parse(readFileSync(resolve(REPO_ROOT, "scripts/vectors/rfc9380-j81.json"), "utf8")) as {
  dst: string;
  vectors: { msg: string; x: string; y: string }[];
};

describe("RFC 9380 Appendix J.8.1 (secp256k1_XMD:SHA-256_SSWU_RO_)", () => {
  it("has the 5 vectors", () => expect(rfc.vectors).toHaveLength(5));
  for (const v of rfc.vectors) {
    it(`hash_to_curve(${JSON.stringify(v.msg.length > 20 ? v.msg.slice(0, 12) + "…" : v.msg)})`, () => {
      expect(hashToCurveXY(v.msg, rfc.dst)).toEqual({ x: v.x, y: v.y });
    });
  }
});

describe("real canary", () => {
  it("is deterministic", () => {
    expect(deriveCanary(REAL_CANARY.msg, REAL_CANARY.dst)).toEqual(deriveCanary(REAL_CANARY.msg, REAL_CANARY.dst));
  });
  it("matches deployments/canary.json", () => {
    const saved = JSON.parse(readFileSync(resolve(REPO_ROOT, "deployments/canary.json"), "utf8"));
    expect(deriveCanary(saved.msg, saved.dst)).toEqual(saved);
  });
  it("changes with the phrase or DST", () => {
    const a = deriveCanary(REAL_CANARY.msg, REAL_CANARY.dst).address;
    expect(deriveCanary(REAL_CANARY.msg + " ", REAL_CANARY.dst).address).not.toBe(a);
    expect(deriveCanary(REAL_CANARY.msg, REAL_CANARY.dst.replace("V1", "V2")).address).not.toBe(a);
  });
});
