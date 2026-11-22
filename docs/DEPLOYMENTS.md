# Deployments

Testnet only: qorechain-diana, EVM chain 9800. Addresses, tx hashes, block numbers and dates. Machine-readable copies live in `deployments/*.json`.

## Demo accounts (eth_secp256k1, coin type 60)

| Name | qor1 | 0x |
|---|---|---|
| deployer (admin) | `qor1l69nm6wn5s999z4t0wtxum3xm58x3z4wghxvu9` | `0xfE8b3De9D3A40a528aaB7B966e6e26DD0e688aae` |
| lp1 | `qor15uwachj8qyczfrfedktxkx2keulhe8htlhmwk9` | `0xa71ddC5e470130248D396d966b1956CF3f7c9eEb` |
| buyer1 | `qor1fhmw6u03zl0llvhxfk4hfzsxrua8reftcxtzjj` | `0x4DF6ED71f117dfFfB2e64Dab748A061f3A71e52B` |
| reporter | `qor1lp0nlay9uredcr965rfetem4chm9nrw8uqpwfz` | `0xf85f3fF485e0F2Dc0CBaA0D395e775c5f6598Dc7` |

## Spike contracts (M0)

Throwaway contracts from S2 (2026-11-22). Not part of Canary.

| Contract | Address | Deploy tx | Block | Route |
|---|---|---|---|---|
| Counter | `0x66b774a7c51089162cfcab2eade7c624135f3a9c` | `0xc3fdc329272b0dfa21fe00c9dde2812292b4d93437ed4f55fcda9073b1146469` | 10575451 | viem |
| PQProbe | `0xc8815608dbf829a9a42e80c3392c17b091a85e0f` | `0x29b69e0eb0cf9672604267e7318e2efeb00f4c5cc10e5951f7329bdd8c1db76f` | 10575452 | viem |
| Counter | `0x95D0A6F4E64989336B776d142AbAf5C675280A3B` | `0xdb5af29daf64fbcaba0d04be865786a43deb7b5ba0eb2973227357499a9a6362` | 10575513 | forge script |

### Network-feature evidence so far

| Feature | Tx (native lane unless 0x) |
|---|---|
| PQC key registration with proof (×4) | `68C64149…D7CC`, `54293291…FB22`, `E3C64EC3…EE55`, `B0782133…CD67` (full hashes in SPIKES.md S1) |
| Hybrid ML-DSA-87 txs (bank sends) | `05E29506…5E8A`, `A0441F4B…9EEB`, `040CB8EB…CB53` |
| EVM window, unscoped | `610C8E8E…BA96`, `264D73FF…E002` |
| EVM window, scoped | `F9D069B9…17F6` (targets PQProbe), `5BFC8518…993E` (targets Counter + PQProbe) |
| PQ-authorised EVM call | `0x45cbdf4f64b719ec1c4f45ff13f583fd2db7822cae405267346b0237fc8085e6` |

## Canary contracts

_Deployed in M2._
