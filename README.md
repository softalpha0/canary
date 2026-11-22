# Canary

**Canary pays out the moment anyone proves the crypto behind Bitcoin and Ethereum keys has been broken, and only post-quantum signatures can move its money.**

A Post-Quantum dApp for the QoreChain **Build Before Q-Day** hackathon. Testnet demonstration only: not insurance, no real funds.

> 🚧 Work in progress. The build plan is in [`docs/plan/`](docs/plan/README.md); spike results are in [`docs/SPIKES.md`](docs/SPIKES.md).

## Repo layout

| Path | What |
|---|---|
| `contracts/` | Foundry project (Solidity 0.8.24) |
| `scripts/` | TypeScript (Node 20+, tsx): accounts, EVM windows, spikes, canary derivation, signing, deploy |
| `app/` | Web app (Vite + React), from M3 |
| `docs/` | Plan, spikes, decisions, deployments, threat model, audit |

## Quick start (developers)

```bash
pnpm install
git submodule update --init --recursive
cp .env.example .env          # then: pnpm accounts create
cd contracts && forge build
```

## License

Apache-2.0
