import { defineChain } from "viem";
import { optionalEnv } from "./lib/env.js";

/**
 * Single source of network config for scripts (AGENT_BRIEF §6).
 * Values per docs/plan/05_QORECHAIN_INTEGRATION.md, overridable from .env.
 */
export const config = {
  cosmosChainId: optionalEnv("CHAIN_ID", "qorechain-diana"),
  evmChainId: Number(optionalEnv("EVM_CHAIN_ID", "9800")),
  evmRpc: optionalEnv("EVM_RPC_URL", "https://evm-testnet.qore.host"),
  cosmosRpc: optionalEnv("RPC_URL", "https://rpc-testnet.qore.host"),
  rest: optionalEnv("REST_URL", "https://api-testnet.qore.host"),
  explorer: optionalEnv("EXPLORER_URL", "https://explore.qore.network"),
  /** Native fee denom; 1 QOR = 1e6 uqor on the native lane, 1e18 wei on the EVM lane. */
  denom: "uqor",
  precompiles: {
    pqcVerify: "0x0000000000000000000000000000000000000a01",
    pqcKeyStatus: "0x0000000000000000000000000000000000000a02",
  },
} as const;

export const qoreTestnet = defineChain({
  id: config.evmChainId,
  name: "QoreChain Testnet",
  nativeCurrency: { name: "QOR", symbol: "QOR", decimals: 18 },
  rpcUrls: { default: { http: [config.evmRpc] } },
});

/** The four demo accounts (docs/plan/02_ARCHITECTURE.md). Env var = <NAME>_MNEMONIC. */
export const ACCOUNT_NAMES = ["deployer", "lp1", "buyer1", "reporter"] as const;
export type AccountName = (typeof ACCOUNT_NAMES)[number];
export const mnemonicVar = (name: AccountName) => `${name.toUpperCase()}_MNEMONIC`;
