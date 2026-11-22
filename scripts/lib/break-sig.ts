import { secp256k1 } from "@noble/curves/secp256k1.js";
import { hexToBytes, recoverAddress, serializeSignature, toHex, type Address, type Hex } from "viem";

/**
 * Sign a 32-byte break digest RAW (no Ethereum message prefix) with a secp256k1 key, returning
 * (v, r, s) with v = recovery + 27, as CanaryRegistry.reportBreak expects. Self-checks with ecrecover semantics.
 */
export async function signBreakDigest(digest: Hex, privateKey: Hex, expected: Address) {
  const bytes = secp256k1.sign(hexToBytes(digest), hexToBytes(privateKey), { prehash: false, format: "recovered" });
  const sig = secp256k1.Signature.fromBytes(bytes, "recovered");
  if (sig.recovery === undefined) throw new Error("no recovery bit");
  const v = sig.recovery + 27;
  const r = toHex(sig.r, { size: 32 });
  const s = toHex(sig.s, { size: 32 });
  const recovered = await recoverAddress({ hash: digest, signature: serializeSignature({ r, s, v: BigInt(v) }) });
  if (recovered.toLowerCase() !== expected.toLowerCase()) {
    throw new Error(`Self-check failed: signature recovers to ${recovered}, expected ${expected}`);
  }
  return { v, r, s };
}
