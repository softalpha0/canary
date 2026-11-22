/**
 * SPIKE S4 fallback (owner waived the MetaMask run): send Counter.increment() from deployer's
 * eth_secp256k1 key with viem inside the open scoped window, then parse the receipt (s4-receipt.ts).
 * Proves: EIP-1559 tx on 9800 admitted by a scoped window + viem receipt parsing. Not proven: MetaMask UI.
 */
import { artifact, fees, publicClient, walletFor } from "../lib/evm.js";
import { loadAccount } from "../lib/qore.js";

const COUNTER = "0x66b774a7c51089162cfcab2eade7c624135f3a9c" as const;
const d = await loadAccount("deployer");
const c = artifact("Counter");
const gas = (await publicClient.estimateGas({ account: d.evm as `0x${string}`, to: COUNTER, data: "0xd09de08a" })) * 125n / 100n;
const hash = await walletFor(d).writeContract({ address: COUNTER, abi: c.abi, functionName: "increment", gas, ...(await fees()) });
console.log(`Counter.increment from deployer via viem: ${hash} (gas limit ${gas})`);
