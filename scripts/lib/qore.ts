/**
 * Native-lane helpers for eth_secp256k1 (coin type 60) accounts.
 *
 * Every @qorechain/sdk call used here was checked against the installed
 * package's type declarations (sdk 0.14.0): deriveUnifiedAccount,
 * EthNativeSigner, buildRegisterPqcKeyMsg, signProofOfPossession,
 * fetchPqcStatus, fetchEvmWindow, openEvmWindowMsg, closeEvmWindowMsg.
 * The REST routes are standard Cosmos SDK routes plus /qorechain/pqc/v1/*.
 */
import {
  EthNativeSigner,
  buildRegisterPqcKeyMsg,
  closeEvmWindowMsg,
  deriveUnifiedAccount,
  fetchEvmWindow,
  fetchPqcStatus,
  openEvmWindowMsg,
  signProofOfPossession,
  type EthBroadcaster,
  type UnifiedAccount,
} from "@qorechain/sdk";
import { config, mnemonicVar, type AccountName } from "../config.js";
import { requireEnv } from "./env.js";

export type { UnifiedAccount };
/** The SDK's message type (cosmjs EncodeObject), without depending on cosmjs directly. */
type EncodeObject = ReturnType<typeof openEvmWindowMsg>;

/** Derive a demo account from its mnemonic in .env. Never logs secrets. */
export async function loadAccount(name: AccountName): Promise<UnifiedAccount> {
  return deriveUnifiedAccount(requireEnv(mnemonicVar(name)));
}

/** Public view of an account: safe to print and commit. */
export function publicInfo(name: string, a: UnifiedAccount) {
  return { name, qor: a.cosmos, evm: a.evm };
}

async function getJson(path: string): Promise<unknown> {
  const res = await fetch(`${config.rest}${path}`);
  const body = await res.json();
  if (!res.ok) throw Object.assign(new Error(`GET ${path} → HTTP ${res.status}: ${JSON.stringify(body)}`), { body });
  return body;
}

/** Bank balance in uqor (native lane, 6 decimals). */
export async function balanceUqor(address: string): Promise<bigint> {
  const b = (await getJson(`/cosmos/bank/v1beta1/balances/${address}/by_denom?denom=${config.denom}`)) as {
    balance?: { amount?: string };
  };
  return BigInt(b.balance?.amount ?? "0");
}

/** account_number and sequence. Throws a clear error for an account the chain has never seen (unfunded). */
export async function accountSequence(address: string): Promise<{ accountNumber: bigint; sequence: bigint }> {
  let body: { account?: Record<string, unknown> };
  try {
    body = (await getJson(`/cosmos/auth/v1beta1/accounts/${address}`)) as typeof body;
  } catch (e) {
    throw new Error(`Account ${address} is not on chain yet. Fund it first (faucet or a transfer from deployer).`, {
      cause: e,
    });
  }
  // BaseAccount fields may sit at the top level or under base_account (vesting/module wrappers).
  const acc = (body.account?.["base_account"] as Record<string, unknown> | undefined) ?? body.account ?? {};
  return { accountNumber: BigInt(String(acc["account_number"] ?? "0")), sequence: BigInt(String(acc["sequence"] ?? "0")) };
}

interface TxResponse {
  txhash: string;
  code: number;
  height: string;
  raw_log: string;
  gas_used: string;
  gas_wanted: string;
  codespace?: string;
}

/** Wait for a tx to be included; returns the final tx_response. */
export async function waitForTx(hash: string, timeoutMs = 60_000): Promise<TxResponse> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const res = await fetch(`${config.rest}/cosmos/tx/v1beta1/txs/${hash}`);
    if (res.ok) {
      const body = (await res.json()) as { tx_response: TxResponse };
      return body.tx_response;
    }
    await new Promise((r) => setTimeout(r, 1500));
  }
  throw new Error(`Tx ${hash} not found after ${timeoutMs / 1000}s`);
}

/** EthBroadcaster over the public REST endpoint (no extra dependency). */
export const restBroadcaster: EthBroadcaster = {
  async broadcastTx(tx: Uint8Array) {
    const res = await fetch(`${config.rest}/cosmos/tx/v1beta1/txs`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ tx_bytes: Buffer.from(tx).toString("base64"), mode: "BROADCAST_MODE_SYNC" }),
    });
    const body = (await res.json()) as { tx_response?: TxResponse };
    const sync = body.tx_response;
    if (!sync) throw new Error(`Broadcast failed: HTTP ${res.status} ${JSON.stringify(body)}`);
    if (sync.code !== 0) {
      return { code: sync.code, transactionHash: sync.txhash, rawLog: `${sync.codespace ?? ""}: ${sync.raw_log}` };
    }
    const final = await waitForTx(sync.txhash);
    return {
      code: final.code,
      transactionHash: final.txhash,
      height: Number(final.height),
      gasUsed: BigInt(final.gas_used),
      gasWanted: BigInt(final.gas_wanted),
      rawLog: final.code === 0 ? "" : `${final.codespace ?? ""}: ${final.raw_log}`,
    };
  },
};

export interface SendOptions {
  /** "classical" only for the bootstrap MsgRegisterPQCKeyV2. */
  signMode?: "hybrid" | "classical";
  gas: bigint;
  /** uqor per gas; the chain floor is 0.1, the SDK default 0.15. */
  gasPriceUqor?: number;
  memo?: string;
}

/** Sign (eth-native, hybrid by default) and broadcast native-lane messages. Throws on a non-zero code. */
export async function sendNative(account: UnifiedAccount, messages: EncodeObject[], opts: SendOptions) {
  const signer = new EthNativeSigner(account, { signMode: opts.signMode ?? "hybrid", rest: config.rest });
  const { accountNumber, sequence } = await accountSequence(account.cosmos);
  const feeAmount = BigInt(Math.ceil(Number(opts.gas) * (opts.gasPriceUqor ?? 0.15)));
  const res = await signer.signAndBroadcast(restBroadcaster, {
    chainId: config.cosmosChainId,
    accountNumber,
    sequence,
    messages,
    fee: { amount: [{ denom: config.denom, amount: feeAmount.toString() }], gas: opts.gas.toString() },
    memo: opts.memo,
  });
  if (res.code !== 0) {
    throw Object.assign(new Error(`Tx ${res.transactionHash} failed: code ${res.code} ${res.rawLog ?? ""}`), res);
  }
  return res;
}

/** Register the account's canonical ML-DSA-87 key WITH proof of possession (classical-signed bootstrap). */
export async function registerPqcKey(account: UnifiedAccount) {
  const status = await fetchPqcStatus({ rest: config.rest, address: account.cosmos });
  if (status.registered) return { alreadyRegistered: true as const, status };
  const proofOfPossession = signProofOfPossession({
    chainId: config.cosmosChainId,
    account: account.cosmos,
    algorithmId: 1,
    keypair: account.pqc,
  });
  const msg = buildRegisterPqcKeyMsg(account.cosmos, {
    pqcKeypair: account.pqc,
    keyType: "hybrid",
    proofOfPossession,
  });
  const res = await sendNative(account, [msg], { signMode: "classical", gas: 600_000n });
  return { alreadyRegistered: false as const, txHash: res.transactionHash, height: res.height };
}

export interface WindowParams {
  blocks: number;
  maxTxs: number;
  /** uqor: value PLUS max fee of every admitted tx. */
  maxValueUqor: bigint;
  allowedTargets?: string[];
  nativeOnly?: boolean;
}

export async function openWindow(account: UnifiedAccount, p: WindowParams) {
  const msg = openEvmWindowMsg({
    sender: account.cosmos,
    blocks: p.blocks,
    maxTxs: p.maxTxs,
    maxValue: p.maxValueUqor,
    ...(p.allowedTargets && p.allowedTargets.length > 0 ? { allowedTargets: p.allowedTargets } : {}),
    ...(p.nativeOnly ? { nativeOnly: true } : {}),
  });
  return sendNative(account, [msg], { gas: 400_000n });
}

export async function closeWindow(account: UnifiedAccount) {
  return sendNative(account, [closeEvmWindowMsg(account.cosmos)], { gas: 400_000n });
}

export const windowStatus = (address: string) => fetchEvmWindow({ rest: config.rest, address });
export const pqcStatus = (address: string) => fetchPqcStatus({ rest: config.rest, address });

export const fmtQor = (uqor: bigint) => `${(Number(uqor) / 1e6).toFixed(6)} QOR`;
