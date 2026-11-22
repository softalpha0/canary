// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICanaryRegistry} from "./interfaces/ICanaryRegistry.sol";
import {PQAuth} from "./lib/PQAuth.sol";

/// @title CoverPool
/// @notice Parametric Q-Day cover for one canary, in native QOR. LPs deposit and earn premiums; buyers pay a
///         premium for cover over a period. When the canary dies, every policy active at that moment can claim
///         its full cover. Money leaves only through ML-DSA-87-authorised withdrawals and claims (checked on-chain
///         with `pqcVerify`), or as a capped bounty to the canary's reporter from free capital.
/// @dev Fully collateralised: activeCover <= balance until settled. `msg.sender` is never trusted for authority:
///      authorised functions take an explicit `owner` and that owner's ML-DSA signature over an action digest.
contract CoverPool is ReentrancyGuard {
    // ------------------------------------------------------------------ types

    struct Config {
        address registry;
        uint256 canaryId;
        address admin;
        uint8 msgMode;
        uint64 minDuration;
        uint64 maxDuration;
        uint64 cooldown;
        uint64 claimWindow;
        uint256 bountyBps;
        uint256 bountyCap;
        uint256 minDeposit;
        uint256 maxRateBps;
        uint256 premiumRateBps;
    }

    struct WithdrawRequest {
        address owner;
        uint128 shares;
        uint64 unlockAt;
        bool closed;
    }

    struct Policy {
        address owner;
        uint128 coverAmount; // wei
        uint64 start; // block.timestamp at purchase
        uint64 expiry; // start + duration
        bool released; // expired, or released at settlement
        bool paid;
        bytes32 noteHash; // P1: hash of a QoreSeal envelope; 0x0 if none
    }

    // ------------------------------------------------------------------ constants

    bytes32 public constant REQUEST_WITHDRAW = keccak256("REQUEST_WITHDRAW");
    bytes32 public constant CANCEL_WITHDRAW = keccak256("CANCEL_WITHDRAW");
    bytes32 public constant EXECUTE_WITHDRAW = keccak256("EXECUTE_WITHDRAW");
    bytes32 public constant CLAIM_PAYOUT = keccak256("CLAIM_PAYOUT");
    bytes32 public constant SET_RATE = keccak256("SET_RATE");
    bytes32 public constant SET_PAUSED = keccak256("SET_PAUSED");

    uint256 internal constant BPS = 10_000;
    uint256 internal constant YEAR = 365 days;
    /// @dev Virtual shares / assets offset against first-depositor inflation attacks.
    uint256 internal constant VIRTUAL_SHARES = 1e3;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    // ------------------------------------------------------------------ immutables

    ICanaryRegistry public immutable registry;
    uint256 public immutable canaryId;
    address public immutable admin;
    uint8 public immutable msgMode;
    uint64 public immutable minDuration;
    uint64 public immutable maxDuration;
    uint64 public immutable cooldown;
    uint64 public immutable claimWindow;
    uint256 public immutable bountyBps;
    uint256 public immutable bountyCap;
    uint256 public immutable minDeposit;
    uint256 public immutable maxRateBps;

    // ------------------------------------------------------------------ state

    uint256 public premiumRateBps; // annual
    bool public paused; // blocks buyCover only

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf; // includes shares locked in requests
    mapping(address => uint256) public lockedShares;

    WithdrawRequest[] public requests;
    Policy[] public policies;

    uint256 public activeCover; // sum of coverAmount over policies neither released nor paid
    bool public bountyPaid;
    bool public settled;
    mapping(address => uint256) public nonces;

    // ------------------------------------------------------------------ events

    event Deposited(address indexed receiver, uint256 assets, uint256 shares);
    event WithdrawRequested(uint256 indexed requestId, address indexed owner, uint256 shares, uint64 unlockAt);
    event WithdrawCancelled(uint256 indexed requestId, address indexed owner);
    event Withdrawn(
        uint256 indexed requestId, address indexed owner, address recipient, uint256 shares, uint256 assets
    );
    event CoverBought(
        uint256 indexed policyId,
        address indexed owner,
        uint256 coverAmount,
        uint256 premium,
        uint64 start,
        uint64 expiry,
        bytes32 noteHash
    );
    event PolicyExpired(uint256 indexed policyId);
    event PayoutClaimed(uint256 indexed policyId, address indexed owner, address recipient, uint256 amount);
    event BountyPaid(address indexed reporter, uint256 amount);
    event Settled(uint256 releasedCover);
    event PremiumRateSet(uint256 bps);
    event PausedSet(bool paused);
    event NonceUsed(address indexed owner, uint256 nonce, bytes32 indexed action);

    // ------------------------------------------------------------------ errors

    error CanaryIsDead();
    error CanaryAlive();
    error Paused();
    error BelowMinDeposit();
    error BadDuration();
    error WrongPremium(uint256 expected);
    error NoCapacity(uint256 available);
    error NotEnoughShares();
    error RequestClosed();
    error NotRequestOwner();
    error CooldownActive(uint64 unlockAt);
    error InsufficientFreeCapital(uint256 needed, uint256 free);
    error NotEligible();
    error ClaimWindowClosed();
    error ClaimWindowOpen();
    error AlreadyPaid();
    error AlreadyReleased();
    error AlreadySettled();
    error BountyAlreadyPaid();
    error RateTooHigh();
    error TransferFailed();
    error ZeroAmount();
    error ZeroAddress();
    error UnknownId();
    error BadConfig();

    // ------------------------------------------------------------------ constructor

    /// @notice Deploy a pool for one canary. The admin must already have a registered, proven ML-DSA-87 key.
    constructor(Config memory c) {
        if (c.registry == address(0) || c.admin == address(0)) revert ZeroAddress();
        if (
            c.minDuration == 0 || c.minDuration > c.maxDuration || c.bountyBps > BPS || c.maxRateBps > BPS
                || c.premiumRateBps > c.maxRateBps || c.msgMode > PQAuth.MODE_QOREX || c.minDeposit == 0
        ) revert BadConfig();
        if (c.canaryId >= ICanaryRegistry(c.registry).count()) revert BadConfig();
        PQAuth.ownerKey(c.admin); // reverts unless registered + proven ML-DSA-87

        registry = ICanaryRegistry(c.registry);
        canaryId = c.canaryId;
        admin = c.admin;
        msgMode = c.msgMode;
        minDuration = c.minDuration;
        maxDuration = c.maxDuration;
        cooldown = c.cooldown;
        claimWindow = c.claimWindow;
        bountyBps = c.bountyBps;
        bountyCap = c.bountyCap;
        minDeposit = c.minDeposit;
        maxRateBps = c.maxRateBps;
        premiumRateBps = c.premiumRateBps;
    }

    // ------------------------------------------------------------------ LP

    /// @notice Deposit QOR for pool shares credited to `receiver`, who must have a registered, proven ML-DSA-87
    ///         key (so they can always authorise a withdrawal later).
    function deposit(address receiver) external payable nonReentrant returns (uint256 shares) {
        (bool dead,) = _death();
        if (dead) revert CanaryIsDead();
        if (msg.value < minDeposit) revert BelowMinDeposit();
        PQAuth.ownerKey(receiver);
        // Inside a payable call the balance already includes msg.value: price on assets before this deposit.
        shares =
            Math.mulDiv(msg.value, totalShares + VIRTUAL_SHARES, address(this).balance - msg.value + VIRTUAL_ASSETS);
        if (shares == 0) revert ZeroAmount();
        totalShares += shares;
        sharesOf[receiver] += shares;
        emit Deposited(receiver, msg.value, shares);
    }

    /// @notice Lock `shares` of `owner` for withdrawal after the cooldown. Authorised by `owner`'s ML-DSA signature.
    /// @dev Locked shares stay exposed to payouts. Allowed after death (withdrawals are never blocked).
    function requestWithdraw(address owner, uint256 shares, uint256 deadline, bytes calldata sig)
        external
        returns (uint256 requestId)
    {
        if (shares == 0) revert ZeroAmount();
        if (shares > sharesOf[owner] - lockedShares[owner]) revert NotEnoughShares();
        _authorize(REQUEST_WITHDRAW, owner, deadline, keccak256(abi.encode(shares)), sig);
        lockedShares[owner] += shares;
        uint64 unlockAt = uint64(block.timestamp) + cooldown;
        requestId = requests.length;
        requests.push(WithdrawRequest(owner, uint128(shares), unlockAt, false));
        emit WithdrawRequested(requestId, owner, shares, unlockAt);
    }

    /// @notice Cancel an open withdrawal request and unlock its shares. Authorised by the request owner.
    function cancelWithdraw(address owner, uint256 requestId, uint256 deadline, bytes calldata sig) external {
        WithdrawRequest storage q = _openRequest(owner, requestId);
        _authorize(CANCEL_WITHDRAW, owner, deadline, keccak256(abi.encode(requestId)), sig);
        q.closed = true;
        lockedShares[owner] -= q.shares;
        emit WithdrawCancelled(requestId, owner);
    }

    /// @notice After the cooldown, burn the request's shares and send their value to `recipient`, limited by free
    ///         capital. Authorised by the request owner; the signature binds `recipient`.
    function executeWithdraw(
        address owner,
        uint256 requestId,
        address payable recipient,
        uint256 deadline,
        bytes calldata sig
    ) external nonReentrant returns (uint256 assets) {
        if (recipient == address(0)) revert ZeroAddress();
        WithdrawRequest storage q = _openRequest(owner, requestId);
        if (block.timestamp < q.unlockAt) revert CooldownActive(q.unlockAt);
        uint256 shares = q.shares;
        assets = toAssets(shares);
        uint256 free = freeAssets();
        if (assets > free) revert InsufficientFreeCapital(assets, free);
        _authorize(EXECUTE_WITHDRAW, owner, deadline, keccak256(abi.encode(requestId, recipient)), sig);
        q.closed = true;
        lockedShares[owner] -= shares;
        sharesOf[owner] -= shares;
        totalShares -= shares;
        emit Withdrawn(requestId, owner, recipient, shares, assets);
        _send(recipient, assets);
    }

    // ------------------------------------------------------------------ cover

    /// @notice Buy `coverAmount` of cover for `duration` seconds, owned by `owner` (who must have a registered,
    ///         proven ML-DSA-87 key to claim later). `msg.value` must equal `quotePremium(coverAmount, duration)`.
    function buyCover(address owner, uint256 coverAmount, uint64 duration, bytes32 noteHash)
        external
        payable
        nonReentrant
        returns (uint256 policyId)
    {
        (bool dead,) = _death();
        if (dead) revert CanaryIsDead();
        if (paused) revert Paused();
        if (coverAmount == 0 || coverAmount > type(uint128).max) revert ZeroAmount();
        if (duration < minDuration || duration > maxDuration) revert BadDuration();
        PQAuth.ownerKey(owner);
        uint256 premium = quotePremium(coverAmount, duration);
        if (msg.value != premium) revert WrongPremium(premium);
        uint256 balance = address(this).balance; // includes the premium
        if (activeCover + coverAmount > balance) revert NoCapacity(balance - activeCover);

        uint64 start = uint64(block.timestamp);
        uint64 expiry = start + duration;
        policyId = policies.length;
        policies.push(Policy(owner, uint128(coverAmount), start, expiry, false, false, noteHash));
        activeCover += coverAmount;
        emit CoverBought(policyId, owner, coverAmount, premium, start, expiry, noteHash);
    }

    /// @notice Release an expired policy's capacity. Anyone may call. After death, only policies that expired at or
    ///         before the death time can be expired (the others are claimable).
    function expire(uint256 policyId) external {
        Policy storage p = _policy(policyId);
        if (settled) revert AlreadySettled();
        if (p.paid) revert AlreadyPaid();
        if (p.released) revert AlreadyReleased();
        if (block.timestamp < p.expiry) revert NotEligible();
        (bool dead, uint64 deadAt) = _death();
        if (dead && p.expiry > deadAt) revert NotEligible();
        p.released = true;
        activeCover -= p.coverAmount;
        emit PolicyExpired(policyId);
    }

    /// @notice After the canary dies, pay an eligible policy's full cover to `recipient`. Authorised by the policy
    ///         owner's ML-DSA signature, which binds `recipient`.
    function claimPayout(uint256 policyId, address payable recipient, uint256 deadline, bytes calldata sig)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (recipient == address(0)) revert ZeroAddress();
        Policy storage p = _policy(policyId);
        (bool dead, uint64 deadAt) = _death();
        if (!dead) revert CanaryAlive();
        if (settled) revert AlreadySettled();
        if (block.timestamp > uint256(deadAt) + claimWindow) revert ClaimWindowClosed();
        if (p.paid) revert AlreadyPaid();
        if (p.released) revert AlreadyReleased();
        if (p.start > deadAt || deadAt >= p.expiry) revert NotEligible();
        _authorize(CLAIM_PAYOUT, p.owner, deadline, keccak256(abi.encode(policyId, recipient)), sig);
        amount = p.coverAmount;
        p.paid = true;
        activeCover -= amount;
        emit PayoutClaimed(policyId, p.owner, recipient, amount);
        _send(recipient, amount);
    }

    /// @notice Pay the reporter's bounty once: min(bountyBps of assets, bountyCap, free assets). Anyone may call.
    function claimBounty() external nonReentrant returns (uint256 amount) {
        (bool dead,) = _death();
        if (!dead) revert CanaryAlive();
        if (bountyPaid) revert BountyAlreadyPaid();
        bountyPaid = true;
        amount = Math.min(Math.min(address(this).balance * bountyBps / BPS, bountyCap), freeAssets());
        address reporter = registry.reporterOf(canaryId);
        emit BountyPaid(reporter, amount);
        _send(payable(reporter), amount);
    }

    /// @notice After the claim window, release all unclaimed cover back to LPs. Anyone may call.
    function finalizeAfterClaimWindow() external {
        (bool dead, uint64 deadAt) = _death();
        if (!dead) revert CanaryAlive();
        if (block.timestamp <= uint256(deadAt) + claimWindow) revert ClaimWindowOpen();
        if (settled) revert AlreadySettled();
        settled = true;
        uint256 released = activeCover;
        activeCover = 0;
        emit Settled(released);
    }

    // ------------------------------------------------------------------ admin

    /// @notice Set the annual premium rate (bps), at most maxRateBps. Authorised by the admin's ML-DSA signature.
    function setPremiumRate(uint256 bps, uint256 deadline, bytes calldata sig) external {
        if (bps > maxRateBps) revert RateTooHigh();
        _authorize(SET_RATE, admin, deadline, keccak256(abi.encode(bps)), sig);
        premiumRateBps = bps;
        emit PremiumRateSet(bps);
    }

    /// @notice Pause or unpause new cover (never blocks withdrawals or claims). Authorised by the admin.
    function setPaused(bool p, uint256 deadline, bytes calldata sig) external {
        _authorize(SET_PAUSED, admin, deadline, keccak256(abi.encode(p)), sig);
        paused = p;
        emit PausedSet(p);
    }

    // ------------------------------------------------------------------ views

    /// @notice The pool's QOR balance.
    function totalAssets() public view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Whether this pool's canary is dead, and when.
    function isDead() external view returns (bool dead, uint64 deadAt) {
        return _death();
    }

    /// @notice What LPs own: all assets while alive; assets minus outstanding liabilities after death.
    function netAssets() public view returns (uint256) {
        (bool dead,) = _death();
        return dead ? _floorSub(address(this).balance, activeCover) : address(this).balance;
    }

    /// @notice The most that may leave the pool to LPs or the bounty without touching cover backing.
    function freeAssets() public view returns (uint256) {
        return _floorSub(address(this).balance, activeCover);
    }

    /// @notice Shares minted for `assets` at the current price (rounded down).
    function toShares(uint256 assets) public view returns (uint256) {
        return Math.mulDiv(assets, totalShares + VIRTUAL_SHARES, netAssets() + VIRTUAL_ASSETS);
    }

    /// @notice Assets redeemable for `shares` at the current price (rounded down).
    function toAssets(uint256 shares) public view returns (uint256) {
        return Math.mulDiv(shares, netAssets() + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    /// @notice Premium for `cover` over `duration` seconds: ceil(cover * rate * duration / (365 days * 10,000)).
    function quotePremium(uint256 cover, uint64 duration) public view returns (uint256) {
        return Math.mulDiv(cover, premiumRateBps * duration, YEAR * BPS, Math.Rounding.Ceil);
    }

    /// @notice The digest `owner` must sign for their next authorised call (uses the current nonces[owner]).
    function actionDigest(bytes32 action, address owner, uint256 deadline, bytes32 paramsHash)
        external
        view
        returns (bytes32)
    {
        return PQAuth.digest(address(this), action, owner, nonces[owner], deadline, paramsHash);
    }

    /// @notice Number of withdrawal requests ever made.
    function requestsCount() external view returns (uint256) {
        return requests.length;
    }

    /// @notice Number of policies ever sold.
    function policiesCount() external view returns (uint256) {
        return policies.length;
    }

    // ------------------------------------------------------------------ internal

    /// @dev Verify `owner`'s ML-DSA signature over the action digest at the current nonce, then consume the nonce.
    ///      Called before any value transfer. A replayed signature fails as PQBadSignature (the nonce moved on).
    function _authorize(bytes32 action, address owner, uint256 deadline, bytes32 paramsHash, bytes calldata sig)
        internal
    {
        uint256 nonce = nonces[owner];
        PQAuth.authorize(address(this), action, owner, nonce, deadline, paramsHash, sig, msgMode);
        nonces[owner] = nonce + 1;
        emit NonceUsed(owner, nonce, action);
    }

    function _death() internal view returns (bool dead, uint64 deadAt) {
        return registry.isDead(canaryId);
    }

    function _openRequest(address owner, uint256 requestId) internal view returns (WithdrawRequest storage q) {
        if (requestId >= requests.length) revert UnknownId();
        q = requests[requestId];
        if (q.closed) revert RequestClosed();
        if (q.owner != owner) revert NotRequestOwner();
    }

    function _policy(uint256 policyId) internal view returns (Policy storage) {
        if (policyId >= policies.length) revert UnknownId();
        return policies[policyId];
    }

    function _send(address payable to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function _floorSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }
}
