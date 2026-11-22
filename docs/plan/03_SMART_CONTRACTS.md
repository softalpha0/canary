# 03 — Smart Contracts

Solidity **0.8.24**, `evm_version = "paris"`, optimizer on (200 runs). Dependencies: `forge-std`, OpenZeppelin Contracts v5 (`ReentrancyGuard`, `Math.mulDiv`). No upgradeability, no proxies.

## Files

| File | Purpose |
|---|---|
| `src/interfaces/IQorePQC.sol` | Interfaces and addresses of the two precompiles |
| `src/lib/PQAuth.sol` | Digest building, key lookup, `pqcVerify` call, fail-closed checks |
| `src/CanaryRegistry.sol` | Canaries and the break proof |
| `src/CoverPool.sol` | LP shares, cover, withdrawals, payouts, bounty, admin |

## IQorePQC.sol

Interfaces as documented on docs.qorechain.io (developer guide → EVM precompiles):

```solidity
address constant PQC_VERIFY     = 0x0000000000000000000000000000000000000a01;
address constant PQC_KEY_STATUS = 0x0000000000000000000000000000000000000a02;

interface IPQCVerify {
    // pubkey 2,592 bytes, signature 4,627 bytes (ML-DSA-87). Returns false on bad input; does not revert.
    function pqcVerify(bytes calldata pubkey, bytes calldata signature, bytes calldata message)
        external view returns (bool valid);
}

interface IPQCKeyStatus {
    // algorithmId 1 = ML-DSA-87. possessionProven is optional at registration: always require it.
    function pqcKeyStatus(address account)
        external view returns (bool registered, uint8 algorithmId, bytes memory pubkey, bool possessionProven);
}
```

Gas (documented): `pqcVerify` 25,000 + 8 per input byte, about 85,000–90,000 per call. `pqcKeyStatus` 2,500 flat.

## PQAuth.sol (library)

```solidity
library PQAuth {
    bytes32 constant DOMAIN_TAG = keccak256("Canary.v1");
    uint8 constant MODE_RAW = 0;
    uint8 constant MODE_QOREX = 1;

    error PQPrecompileUnavailable();   // empty or failed returndata: precompile inactive → fail closed
    error PQKeyNotRegistered(address owner);
    error PQKeyNotProven(address owner);
    error PQWrongAlgorithm(address owner, uint8 algorithmId);
    error PQBadSignature();
    error PQExpired(uint256 deadline);

    function digest(address verifyingContract, bytes32 action, address owner,
                    uint256 nonce, uint256 deadline, bytes32 paramsHash) internal view returns (bytes32);

    function ownerKey(address owner) internal view returns (bytes memory pubkey);   // low-level staticcall to 0x…0a02

    function verify(address owner, bytes32 d, bytes calldata sig, uint8 mode) internal view; // reverts on failure
}
```

Rules:
1. `digest(...)` = `keccak256(abi.encode(DOMAIN_TAG, block.chainid, verifyingContract, action, owner, nonce, deadline, paramsHash))`.
2. `ownerKey`: low-level `staticcall` to `PQC_KEY_STATUS`. Revert `PQPrecompileUnavailable` if the call fails or returndata is shorter than 128 bytes. Decode; require `registered`, `algorithmId == 1`, `possessionProven`, and `pubkey.length == 2592`.
3. `verify`: build the message by mode (below). Low-level `staticcall` to `PQC_VERIFY` with `abi.encodeCall(IPQCVerify.pqcVerify, (pubkey, sig, message))`. Revert `PQPrecompileUnavailable` if the call fails or returndata is shorter than 32 bytes. Revert `PQBadSignature` unless the decoded bool is `true`. Also require `sig.length == 4627`.
4. Message by mode:
   - `MODE_RAW`: `abi.encodePacked(d)` (32 bytes).
   - `MODE_QOREX`: `bytes.concat(bytes("qorechain-msg-v1|qorechain-diana|"), _encodeForQoreX(d))`. `_encodeForQoreX` is fixed by **SPIKE S3** (expected candidate: lowercase hex with `0x`, 66 ASCII bytes). Until S3 passes, the deployed mode is `MODE_RAW`.
5. The caller consumes the nonce **before** any external value transfer.

## CanaryRegistry.sol

Immutable after deployment. Holds no funds. No admin.

### Storage

```solidity
struct Canary {
    address addr;        // EVM address of the canary public key
    bool    isTest;      // true = test canary (key held by the team, for demos)
    uint64  deadAt;      // 0 while alive
    address reporter;    // who proved the break
    string  label;       // e.g. "Canary #1 (secp256k1)" / "TEST canary"
    string  phrase;      // hash-to-curve input message; "" for the test canary
    string  dst;         // hash-to-curve domain separation tag; "" for the test canary
}
Canary[] public canaries;
bytes32 constant BREAK_TAG = keccak256("Canary.break.v1");
```

### Functions

| Function | Access | Behaviour |
|---|---|---|
| `constructor(Canary[] memory initial)` | deploy | Registers canaries 0..n. Index 0 = real canary, index 1 = test canary. Requires `deadAt == 0` and non-zero `addr`. |
| `breakDigest(uint256 id, address reporter) view returns (bytes32)` | public | `keccak256(abi.encode(BREAK_TAG, block.chainid, address(this), id, reporter))` |
| `reportBreak(uint256 id, address reporter, uint8 v, bytes32 r, bytes32 s)` | anyone | Requires alive and `reporter != address(0)`. `ecrecover(breakDigest(id, reporter), v, r, s)` must equal `canaries[id].addr` (and be non-zero). Sets `deadAt = block.timestamp`, `reporter`. Emits `CanaryDied`. |
| `isDead(uint256 id) view returns (bool, uint64)` | public | `(deadAt != 0, deadAt)` |
| `reporterOf(uint256 id) view returns (address)` | public | The recorded reporter (zero while alive). CoverPool pays the bounty here. |
| `count() view returns (uint256)` | public | number of canaries |

The break digest is signed **raw**: no `\x19Ethereum Signed Message` prefix. Putting `reporter` inside the digest means a copied proof cannot redirect the bounty.

### Events and errors

```solidity
event CanaryDied(uint256 indexed id, address indexed reporter, uint64 deadAt, bool isTest);
error UnknownCanary(uint256 id);
error AlreadyDead(uint256 id);
error InvalidBreakSignature();
error ZeroReporter();
```

## CoverPool.sol

One instance per canary. Inherits `ReentrancyGuard`. Holds native QOR.

### Immutable configuration (constructor)

| Param | Real pool | Test pool | Notes |
|---|---|---|---|
| `registry`, `canaryId` | registry, 0 | registry, 1 | |
| `admin` | deployer | deployer | Must have a registered, proven ML-DSA key at deploy (checked) |
| `msgMode` | from S3 | from S3 | `MODE_RAW` or `MODE_QOREX` |
| `minDuration` / `maxDuration` | 1 day / 365 days | 60 s / 30 days | |
| `cooldown` | 3 days | 120 s | Withdrawal request → execute |
| `claimWindow` | 30 days | 1 hour | After death |
| `bountyBps` / `bountyCap` | 100 / 10 QOR | 100 / 1 QOR | Bounty = min(bps of assets, cap, free assets) |
| `minDeposit` | 0.01 QOR | 0.01 QOR | Blocks dust and share-price games |
| `maxRateBps` | 5,000 | 5,000 | Ceiling for admin rate changes |

### Mutable state

```solidity
uint256 public premiumRateBps;   // annual, e.g. 100 = 1%/yr (real), 2000 = 20%/yr (test, visible in demo)
bool    public paused;           // blocks buyCover only

uint256 public totalShares;
mapping(address => uint256) public sharesOf;     // includes shares locked in requests
mapping(address => uint256) public lockedShares;

struct WithdrawRequest { address owner; uint128 shares; uint64 unlockAt; bool closed; }
WithdrawRequest[] public requests;

struct Policy {
    address owner;
    uint128 coverAmount;   // wei
    uint64  start;         // block.timestamp at purchase
    uint64  expiry;        // start + duration
    bool    released;      // expired or released at settlement
    bool    paid;
    bytes32 noteHash;      // P1: hash of the QoreSeal envelope; 0x0 if none
}
Policy[] public policies;

uint256 public activeCover;      // sum of coverAmount over policies neither released nor paid
bool    public bountyPaid;
bool    public settled;          // after the claim window closes
mapping(address => uint256) public nonces;
```

### Definitions

- `totalAssets()` = `address(this).balance`.
- `isDead()` = `registry.isDead(canaryId)`.
- `netAssets()` = alive ? `totalAssets()` : `totalAssets() - activeCover` (floor 0). After death, LPs own only what is left after liabilities.
- `freeAssets()` = `totalAssets() - activeCover` (floor 0). Maximum that may leave the pool to LPs or the bounty.
- Share maths with a virtual offset against inflation attacks:
  - `toShares(assets) = mulDiv(assets, totalShares + 1e3, netAssets() + 1)`
  - `toAssets(shares) = mulDiv(shares, netAssets() + 1, totalShares + 1e3)`
  - Round **down** when giving to users, **up** when taking.
- `quotePremium(cover, duration)` = `ceilDiv(cover * premiumRateBps * duration, 365 days * 10_000)`.

### Functions

`A(...)` = PQ-authorised: takes `deadline` and `bytes calldata sig`, builds the digest with the listed `ACTION` and `paramsHash`, checks `nonce == nonces[owner]`, calls `PQAuth.verify`, then increments `nonces[owner]`.

| Function | Auth | Rules |
|---|---|---|
| `deposit(address receiver) payable` | none | Alive; `msg.value >= minDeposit`; `receiver` has a registered, proven key (`PQAuth.ownerKey`). Shares are priced on assets **excluding** this deposit: inside a payable call `address(this).balance` already includes `msg.value`, so use `netAssets() - msg.value`. Emits `Deposited`. |
| `requestWithdraw(address owner, uint256 shares, deadline, sig)` | `A` — `REQUEST_WITHDRAW`, params `(shares)` | `shares <= sharesOf - lockedShares`. Locks shares. `unlockAt = now + cooldown`. Locked shares stay exposed to payouts. Emits `WithdrawRequested(id, …)`. |
| `cancelWithdraw(address owner, uint256 requestId, deadline, sig)` | `A` — `CANCEL_WITHDRAW`, params `(requestId)` | Request open and owned by `owner`. Unlocks. Emits `WithdrawCancelled`. |
| `executeWithdraw(address owner, uint256 requestId, address payable recipient, deadline, sig)` | `A` — `EXECUTE_WITHDRAW`, params `(requestId, recipient)` | `now >= unlockAt`; open; `assets = toAssets(shares)`; `assets <= freeAssets()` else `InsufficientFreeCapital(assets, free)`. Burn shares, close request, then send. `nonReentrant`. Emits `Withdrawn`. |
| `buyCover(address owner, uint256 coverAmount, uint64 duration, bytes32 noteHash) payable` | none | Alive; not paused; duration within bounds; `owner` has a registered, proven key; `msg.value == quotePremium(...)`; after adding the premium, `activeCover + coverAmount <= totalAssets()`. Creates policy, `activeCover += coverAmount`. Emits `CoverBought`. |
| `expire(uint256 policyId)` | anyone | Not released or paid; `now >= expiry`; if dead, also `expiry <= deadAt`. Sets `released`, `activeCover -= cover`. Emits `PolicyExpired`. |
| `claimPayout(uint256 policyId, address payable recipient, deadline, sig)` | `A` by `policy.owner` — `CLAIM_PAYOUT`, params `(policyId, recipient)` | Dead; not settled; `now <= deadAt + claimWindow`; `start <= deadAt < expiry`; not paid or released. Set `paid`, `activeCover -= cover`, then send `coverAmount`. `nonReentrant`. Emits `PayoutClaimed`. |
| `claimBounty()` | anyone | Dead; not yet paid. `amount = min(totalAssets()*bountyBps/10_000, bountyCap, freeAssets())`. Pays the registry's recorded `reporter`. `nonReentrant`. Emits `BountyPaid`. |
| `finalizeAfterClaimWindow()` | anyone | Dead; `now > deadAt + claimWindow`; not settled. `settled = true`; `activeCover = 0` (unclaimed cover returns to LPs). Emits `Settled(released)`. |
| `setPremiumRate(uint256 bps, deadline, sig)` | `A` by `admin` — `SET_RATE`, params `(bps)` | `bps <= maxRateBps`. Emits `PremiumRateSet`. |
| `setPaused(bool p, deadline, sig)` | `A` by `admin` — `SET_PAUSED`, params `(p)` | Pausing blocks `buyCover` only. Emits `PausedSet`. |
| Views | — | `quotePremium`, `toShares`, `toAssets`, `netAssets`, `freeAssets`, `policiesOf(owner)` (P1, or index from events), `requestsCount`, `policiesCount`, `actionDigest(action, owner, deadline, paramsHash)` (uses the current `nonces[owner]`, exactly as the next authorised call will) |

`paramsHash` is always `keccak256(abi.encode(<params in the order listed>))`. Action constants are `keccak256("<ACTION_NAME>")`. Expose `actionDigest` as a view so scripts and the app build the same bytes the contract checks; tests must assert the off-chain builder and the view agree.

### Events

```solidity
event Deposited(address indexed receiver, uint256 assets, uint256 shares);
event WithdrawRequested(uint256 indexed requestId, address indexed owner, uint256 shares, uint64 unlockAt);
event WithdrawCancelled(uint256 indexed requestId, address indexed owner);
event Withdrawn(uint256 indexed requestId, address indexed owner, address recipient, uint256 shares, uint256 assets);
event CoverBought(uint256 indexed policyId, address indexed owner, uint256 coverAmount, uint256 premium, uint64 start, uint64 expiry, bytes32 noteHash);
event PolicyExpired(uint256 indexed policyId);
event PayoutClaimed(uint256 indexed policyId, address indexed owner, address recipient, uint256 amount);
event BountyPaid(address indexed reporter, uint256 amount);
event Settled(uint256 releasedCover);
event PremiumRateSet(uint256 bps);
event PausedSet(bool paused);
event NonceUsed(address indexed owner, uint256 nonce, bytes32 indexed action);
```

### Errors

`CanaryIsDead`, `CanaryAlive`, `Paused`, `BelowMinDeposit`, `BadDuration`, `WrongPremium(uint256 expected)`, `NoCapacity(uint256 available)`, `NotEnoughShares`, `RequestClosed`, `NotRequestOwner`, `CooldownActive(uint64 unlockAt)`, `InsufficientFreeCapital(uint256 needed, uint256 free)`, `NotEligible`, `ClaimWindowClosed`, `ClaimWindowOpen`, `AlreadyPaid`, `AlreadyReleased`, `AlreadySettled`, `BountyAlreadyPaid`, `BadNonce(uint256 expected)`, `RateTooHigh`, `TransferFailed`, plus the `PQAuth` errors.

### Invariants (must hold after every call; fuzz them)

1. **Solvency:** until settled, `address(this).balance >= activeCover`.
2. **Shares:** the sum of `sharesOf` over all holders equals `totalShares`; `lockedShares[a] <= sharesOf[a]`.
3. **Once only:** a policy is paid at most once, and never both paid and released.
4. **Authority:** QOR leaves the pool only through `executeWithdraw` (owner's ML-DSA signature), `claimPayout` (policy owner's ML-DSA signature) or `claimBounty` (to the registry's reporter, from free assets only).
5. **Replay:** a signature succeeds at most once; any change to owner, params, contract, chain, nonce or deadline makes it fail.
6. **Fail closed:** if either precompile returns empty data, every authorised function reverts.
7. **After death:** no deposits and no new cover; LP withdrawals never reduce the balance below `activeCover`.

### Gas expectations (record real numbers in `docs/DEPLOYMENTS.md`)

An authorised call carries a 4,627-byte signature, so expect roughly 250k–350k gas (QVault measured about 0.3M for a PQ withdrawal). At the 0.1 uqor/gas floor that is about 0.03 QOR per call. Set explicit gas limits in scripts; estimation may fail on this chain.
