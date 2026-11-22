// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {CanaryRegistry} from "../src/CanaryRegistry.sol";
import {CoverPool} from "../src/CoverPool.sol";
import {PQAuth} from "../src/lib/PQAuth.sol";
import {CoverPoolBase} from "./CoverPoolBase.sol";
import {PQTestBase} from "./PQTestBase.sol";

/// @notice Drives random sequences of every pool action across several actors, tracking ghost state.
contract PoolHandler is PQTestBase {
    CoverPool public pool;
    CanaryRegistry public reg;
    uint256 internal canaryKey;
    address internal reporter;
    address[] public actors;

    // ghost accounting
    uint256 public ghostIn; // QOR in (deposits + premiums)
    uint256 public ghostOut; // QOR out (withdrawals + payouts + bounty)
    uint256 public depositsAfterDeath;
    uint256 public coverAfterDeath;
    uint256 public replaySuccesses;
    uint256 public withdrawalsBelowLiabilities;
    mapping(uint256 => uint256) public payoutsPerPolicy;
    mapping(bytes4 => uint256) public calls;

    // last successful authorised call, for replay attempts
    bytes internal lastCall;

    constructor(CoverPool p, CanaryRegistry r, uint256 key, address rep, address[] memory a) {
        pool = p;
        reg = r;
        canaryKey = key;
        reporter = rep;
        actors = a;
        vm.deal(address(this), 1e30);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _dead() internal view returns (bool d) {
        (d,) = reg.isDead(1);
    }

    function _sig(address signer, bytes32 action, address owner, uint256 dl, bytes32 ph)
        internal
        view
        returns (bytes memory)
    {
        return pqSign(signer, pool.actionDigest(action, owner, dl, ph));
    }

    // ---------------------------------------------------------------- actions

    function deposit(uint256 actorSeed, uint256 amount) external {
        amount = bound(amount, 0.01 ether, 100 ether);
        address a = _actor(actorSeed);
        bool deadBefore = _dead();
        try pool.deposit{value: amount}(a) {
            ghostIn += amount;
            if (deadBefore) depositsAfterDeath++;
            calls[this.deposit.selector]++;
        } catch {}
    }

    function buyCover(uint256 actorSeed, uint256 cover, uint256 duration) external {
        duration = bound(duration, 60, 1 days);
        uint256 free = pool.freeAssets();
        if (free < 1e15) return;
        cover = bound(cover, 1e15, free);
        address a = _actor(actorSeed);
        uint256 premium = pool.quotePremium(cover, uint64(duration));
        bool deadBefore = _dead();
        try pool.buyCover{value: premium}(a, cover, uint64(duration), bytes32(0)) {
            ghostIn += premium;
            if (deadBefore) coverAfterDeath++;
            calls[this.buyCover.selector]++;
        } catch {}
    }

    function requestWithdraw(uint256 actorSeed, uint256 fraction) external {
        address a = _actor(actorSeed);
        uint256 avail = pool.sharesOf(a) - pool.lockedShares(a);
        if (avail == 0) return;
        uint256 shares = bound(fraction, 1, avail);
        uint256 dl = block.timestamp + 600;
        bytes memory sig = _sig(a, pool.REQUEST_WITHDRAW(), a, dl, keccak256(abi.encode(shares)));
        bytes memory data = abi.encodeCall(CoverPool.requestWithdraw, (a, shares, dl, sig));
        (bool ok,) = address(pool).call(data);
        if (ok) {
            lastCall = data;
            calls[this.requestWithdraw.selector]++;
        }
    }

    function cancelWithdraw(uint256 reqSeed) external {
        uint256 n = pool.requestsCount();
        if (n == 0) return;
        uint256 id = reqSeed % n;
        (address owner,,, bool closed) = pool.requests(id);
        if (closed) return;
        uint256 dl = block.timestamp + 600;
        bytes memory sig = _sig(owner, pool.CANCEL_WITHDRAW(), owner, dl, keccak256(abi.encode(id)));
        bytes memory data = abi.encodeCall(CoverPool.cancelWithdraw, (owner, id, dl, sig));
        (bool ok,) = address(pool).call(data);
        if (ok) {
            lastCall = data;
            calls[this.cancelWithdraw.selector]++;
        }
    }

    function executeWithdraw(uint256 reqSeed) external {
        uint256 n = pool.requestsCount();
        if (n == 0) return;
        uint256 id = reqSeed % n;
        (address owner,, uint64 unlockAt, bool closed) = pool.requests(id);
        if (closed) return;
        if (block.timestamp < unlockAt) vm.warp(unlockAt);
        address recipient = address(uint160(uint256(keccak256(abi.encode("recipient", id)))));
        uint256 dl = block.timestamp + 600;
        bytes memory sig = _sig(owner, pool.EXECUTE_WITHDRAW(), owner, dl, keccak256(abi.encode(id, recipient)));
        bytes memory data = abi.encodeCall(CoverPool.executeWithdraw, (owner, id, payable(recipient), dl, sig));
        uint256 before = recipient.balance;
        (bool ok,) = address(pool).call(data);
        if (ok) {
            ghostOut += recipient.balance - before;
            if (!pool.settled() && address(pool).balance < pool.activeCover()) withdrawalsBelowLiabilities++;
            lastCall = data;
            calls[this.executeWithdraw.selector]++;
        }
    }

    /// @dev Scan from the seed for an expirable policy (no time travel: warping here would race the clock
    ///      past every claim window and starve the claim path).
    function expire(uint256 policySeed) external {
        uint256 n = pool.policiesCount();
        for (uint256 k = 0; k < n; ++k) {
            uint256 id = (policySeed % n + k) % n;
            (,,, uint64 expiry, bool released, bool paid,) = pool.policies(id);
            if (released || paid || block.timestamp < expiry) continue;
            try pool.expire(id) {
                calls[this.expire.selector]++;
                return;
            } catch {}
        }
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 30 minutes));
    }

    function kill() external {
        if (_dead()) return;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(canaryKey, reg.breakDigest(1, reporter));
        reg.reportBreak(1, reporter, v, r, s);
        calls[this.kill.selector]++;
    }

    /// @dev Scan from the seed for a claimable policy; if none, try the seed's policy anyway (exercises reverts).
    function claimPayout(uint256 policySeed) external {
        uint256 n = pool.policiesCount();
        if (n == 0) return;
        uint256 id = policySeed % n;
        (bool dead, uint64 deadAt) = reg.isDead(1);
        if (dead) {
            for (uint256 k = 0; k < n; ++k) {
                uint256 c = (policySeed % n + k) % n;
                (,, uint64 start, uint64 expiry, bool released, bool paid,) = pool.policies(c);
                if (!released && !paid && start <= deadAt && deadAt < expiry) {
                    id = c;
                    break;
                }
            }
        }
        (address owner,,,,,,) = pool.policies(id);
        address recipient = address(uint160(uint256(keccak256(abi.encode("claim", id)))));
        uint256 dl = block.timestamp + 600;
        bytes memory sig = _sig(owner, pool.CLAIM_PAYOUT(), owner, dl, keccak256(abi.encode(id, recipient)));
        bytes memory data = abi.encodeCall(CoverPool.claimPayout, (id, payable(recipient), dl, sig));
        uint256 before = recipient.balance;
        (bool ok,) = address(pool).call(data);
        if (ok) {
            ghostOut += recipient.balance - before;
            payoutsPerPolicy[id]++;
            lastCall = data;
            calls[this.claimPayout.selector]++;
        }
    }

    function claimBounty() external {
        uint256 before = reporter.balance;
        try pool.claimBounty() {
            ghostOut += reporter.balance - before;
            calls[this.claimBounty.selector]++;
        } catch {}
    }

    function finalize() external {
        try pool.finalizeAfterClaimWindow() {
            calls[this.finalize.selector]++;
        } catch {}
    }

    /// @dev Re-send the last successful authorised call verbatim: it must never succeed twice.
    function replay() external {
        if (lastCall.length == 0) return;
        (bool ok,) = address(pool).call(lastCall);
        if (ok) replaySuccesses++;
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }
}

contract CoverPoolInvariantTest is CoverPoolBase {
    PoolHandler internal handler;
    address internal lp3 = makeAddr("lp3");

    function setUp() public override {
        super.setUp();
        registerKey(lp3);
        address[] memory a = new address[](4);
        a[0] = lp1;
        a[1] = lp2;
        a[2] = buyer;
        a[3] = lp3;
        handler = new PoolHandler(pool, reg, TEST_CANARY_KEY, reporter, a);
        targetContract(address(handler));
        bytes4[] memory sel = new bytes4[](13);
        sel[0] = PoolHandler.deposit.selector;
        sel[1] = PoolHandler.deposit.selector; // weight deposits
        sel[2] = PoolHandler.buyCover.selector;
        sel[3] = PoolHandler.buyCover.selector;
        sel[4] = PoolHandler.requestWithdraw.selector;
        sel[5] = PoolHandler.cancelWithdraw.selector;
        sel[6] = PoolHandler.executeWithdraw.selector;
        sel[7] = PoolHandler.expire.selector;
        sel[8] = PoolHandler.warp.selector;
        sel[9] = PoolHandler.kill.selector;
        sel[10] = PoolHandler.claimPayout.selector;
        sel[11] = PoolHandler.claimBounty.selector;
        sel[12] = PoolHandler.replay.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sel}));
        // finalize is reached via its own selector set below so settlement happens in some runs
        bytes4[] memory sel2 = new bytes4[](1);
        sel2[0] = PoolHandler.finalize.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sel2}));
    }

    /// 1. Solvency: until settled, balance >= activeCover.
    function invariant_solvency() public view {
        if (!pool.settled()) assertGe(address(pool).balance, pool.activeCover());
        assertEq(handler.withdrawalsBelowLiabilities(), 0);
    }

    /// 2. Shares: sum of sharesOf == totalShares; locked <= shares.
    function invariant_shares() public view {
        uint256 sum;
        for (uint256 i = 0; i < handler.actorsLength(); ++i) {
            address a = handler.actors(i);
            sum += pool.sharesOf(a);
            assertLe(pool.lockedShares(a), pool.sharesOf(a));
        }
        assertEq(sum, pool.totalShares());
    }

    /// 3. Once only: a policy is paid at most once and never both paid and released;
    ///    activeCover equals the sum of open policies until settlement.
    function invariant_policiesOnceOnly() public view {
        uint256 open;
        uint256 n = pool.policiesCount();
        for (uint256 i = 0; i < n; ++i) {
            (, uint128 cover,,, bool released, bool paid,) = pool.policies(i);
            assertFalse(released && paid);
            assertLe(handler.payoutsPerPolicy(i), 1);
            if (!released && !paid) open += cover;
        }
        if (!pool.settled()) assertEq(pool.activeCover(), open);
        else assertEq(pool.activeCover(), 0);
    }

    /// 4. Authority: QOR leaves only through executeWithdraw, claimPayout or claimBounty — the balance equals
    ///    everything that came in minus what those three paid out.
    function invariant_noLeaks() public view {
        assertEq(address(pool).balance, handler.ghostIn() - handler.ghostOut());
    }

    /// 5. Replay: a successful authorised call never succeeds a second time.
    function invariant_noReplay() public view {
        assertEq(handler.replaySuccesses(), 0);
    }

    /// 7. After death: no deposits and no new cover.
    function invariant_afterDeath() public view {
        assertEq(handler.depositsAfterDeath(), 0);
        assertEq(handler.coverAfterDeath(), 0);
    }

    /// Bounty never exceeds its cap.
    function invariant_bountyCapped() public view {
        assertLe(reporter.balance, pool.bountyCap());
    }

    /// @dev Guards against a vacuous invariant suite: a pseudo-random 3,000-step drive of the handler must make
    ///      every pool path succeed at least once (deposit, cover, request, cancel, execute, expire, death,
    ///      claim, bounty, settlement), while all invariants still hold at the end.
    function test_handlerReachesEveryPath() public {
        bytes4[12] memory s = [
            PoolHandler.deposit.selector,
            PoolHandler.buyCover.selector,
            PoolHandler.requestWithdraw.selector,
            PoolHandler.cancelWithdraw.selector,
            PoolHandler.executeWithdraw.selector,
            PoolHandler.expire.selector,
            PoolHandler.warp.selector,
            PoolHandler.claimPayout.selector,
            PoolHandler.claimBounty.selector,
            PoolHandler.replay.selector,
            PoolHandler.kill.selector,
            PoolHandler.finalize.selector
        ];
        for (uint256 i = 0; i < 3000; ++i) {
            uint256 r = uint256(keccak256(abi.encode(i)));
            uint256 k = r % (i < 1500 ? 10 : 12); // no death/settlement in the first half
            (bool ok,) = address(handler).call(abi.encodeWithSelector(s[k], r >> 8, r >> 64, r >> 128));
            assertTrue(ok);
        }
        bytes4[10] memory mustSucceed = [
            PoolHandler.deposit.selector,
            PoolHandler.buyCover.selector,
            PoolHandler.requestWithdraw.selector,
            PoolHandler.cancelWithdraw.selector,
            PoolHandler.executeWithdraw.selector,
            PoolHandler.expire.selector,
            PoolHandler.kill.selector,
            PoolHandler.claimPayout.selector,
            PoolHandler.claimBounty.selector,
            PoolHandler.finalize.selector
        ];
        for (uint256 j = 0; j < mustSucceed.length; ++j) {
            emit log_named_uint(vm.toString(mustSucceed[j]), handler.calls(mustSucceed[j]));
        }
        for (uint256 j = 0; j < mustSucceed.length; ++j) {
            assertGt(handler.calls(mustSucceed[j]), 0, "path never succeeded");
        }
        invariant_solvency();
        invariant_shares();
        invariant_policiesOnceOnly();
        invariant_noLeaks();
        invariant_noReplay();
        invariant_afterDeath();
        invariant_bountyCapped();
    }
}
