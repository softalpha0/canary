/**
 * Canary derivation (docs/plan/04_CANARY_KEY.md): RFC 9380 hash_to_curve, suite
 * secp256k1_XMD:SHA-256_SSWU_RO_ (random-oracle variant, NOT encode_to_curve), with Canary's own DST.
 * The point is derived directly from a public phrase, so nobody ever chose (or knows) its discrete log.
 * API checked against the installed @noble/curves 2.4.0: secp256k1_hasher.hashToCurve(msg, { DST }).
 */
import { secp256k1_hasher } from "@noble/curves/secp256k1.js";
import { qoreAddresses } from "@qorechain/sdk";
import { bytesToHex, keccak256, getAddress, type Address, type Hex } from "viem";

export const REAL_CANARY = {
  msg: "QoreChain Canary 2026 #1",
  dst: "CANARY-V1-QORECHAIN_XMD:SHA-256_SSWU_RO_",
} as const;

export interface DerivedCanary {
  msg: string;
  dst: string;
  x: Hex;
  y: Hex;
  /** Uncompressed 04‖X‖Y */
  pubkey: Hex;
  address: Address;
  qor: string;
}

/** hash_to_curve(msg) → affine point (x, y) as 32-byte big-endian hex (no 0x). */
export function hashToCurveXY(msg: string, dst: string): { x: string; y: string } {
  const p = secp256k1_hasher.hashToCurve(new TextEncoder().encode(msg), { DST: dst }).toAffine();
  return { x: p.x.toString(16).padStart(64, "0"), y: p.y.toString(16).padStart(64, "0") };
}

export function deriveCanary(msg: string, dst: string): DerivedCanary {
  const { x, y } = hashToCurveXY(msg, dst);
  // EVM address = last 20 bytes of keccak256(X ‖ Y)
  const address = getAddress(`0x${keccak256(`0x${x}${y}`).slice(-40)}`);
  return {
    msg,
    dst,
    x: `0x${x}`,
    y: `0x${y}`,
    pubkey: `0x04${x}${y}`,
    address,
    qor: qoreAddresses({ evm: address }).cosmos,
  };
}

export { bytesToHex };
