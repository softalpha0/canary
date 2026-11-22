/**
 * Off-chain mirror of PQAuth.digest and CoverPool's action constants / paramsHash rules
 * (docs/plan/02_ARCHITECTURE.md §The action digest, 03_SMART_CONTRACTS.md).
 * The contract view `actionDigest` is the source of truth; this builder is tested against the
 * Foundry-exported vector (contracts/test/vectors/digest.json) so both stay byte-identical.
 */
import { encodeAbiParameters, keccak256, toBytes, type Address, type Hex } from "viem";

export const DOMAIN_TAG = keccak256(toBytes("Canary.v1"));

export const ACTIONS = {
  REQUEST_WITHDRAW: keccak256(toBytes("REQUEST_WITHDRAW")),
  CANCEL_WITHDRAW: keccak256(toBytes("CANCEL_WITHDRAW")),
  EXECUTE_WITHDRAW: keccak256(toBytes("EXECUTE_WITHDRAW")),
  CLAIM_PAYOUT: keccak256(toBytes("CLAIM_PAYOUT")),
  SET_RATE: keccak256(toBytes("SET_RATE")),
  SET_PAUSED: keccak256(toBytes("SET_PAUSED")),
} as const;
export type ActionName = keyof typeof ACTIONS;

/** keccak256(abi.encode(<params in the order listed in 03_SMART_CONTRACTS.md>)). */
export const paramsHash = {
  REQUEST_WITHDRAW: (shares: bigint) => keccak256(encodeAbiParameters([{ type: "uint256" }], [shares])),
  CANCEL_WITHDRAW: (requestId: bigint) => keccak256(encodeAbiParameters([{ type: "uint256" }], [requestId])),
  EXECUTE_WITHDRAW: (requestId: bigint, recipient: Address) =>
    keccak256(encodeAbiParameters([{ type: "uint256" }, { type: "address" }], [requestId, recipient])),
  CLAIM_PAYOUT: (policyId: bigint, recipient: Address) =>
    keccak256(encodeAbiParameters([{ type: "uint256" }, { type: "address" }], [policyId, recipient])),
  SET_RATE: (bps: bigint) => keccak256(encodeAbiParameters([{ type: "uint256" }], [bps])),
  SET_PAUSED: (paused: boolean) => keccak256(encodeAbiParameters([{ type: "bool" }], [paused])),
};

export interface DigestInput {
  chainId: bigint;
  verifyingContract: Address;
  action: Hex;
  owner: Address;
  nonce: bigint;
  deadline: bigint;
  paramsHash: Hex;
}

/** keccak256(abi.encode(DOMAIN_TAG, chainid, verifyingContract, action, owner, nonce, deadline, paramsHash)). */
export function actionDigest(i: DigestInput): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "uint256" },
        { type: "address" },
        { type: "bytes32" },
        { type: "address" },
        { type: "uint256" },
        { type: "uint256" },
        { type: "bytes32" },
      ],
      [DOMAIN_TAG, i.chainId, i.verifyingContract, i.action, i.owner, i.nonce, i.deadline, i.paramsHash],
    ),
  );
}
