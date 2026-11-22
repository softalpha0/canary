// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {CoverPool} from "../src/CoverPool.sol";
import {PQAuth} from "../src/lib/PQAuth.sol";
import {CoverPoolBase} from "./CoverPoolBase.sol";

/// @notice Re-enters the pool from its receive hook.
contract Reenterer {
    CoverPool internal pool;
    bytes internal payload;

    constructor(CoverPool p) {
        pool = p;
    }

    function arm(bytes calldata data) external {
        payload = data;
    }

    receive() external payable {
        (bool ok, bytes memory ret) = address(pool).call(payload);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}

contract RejectingReceiver {
    receive() external payable {
        revert("no");
    }
}

contract CoverPoolTest is CoverPoolBase {
    // ================================================================ constructor

    function test_constructor_setsConfig() public view {
        assertEq(address(pool.registry()), address(reg));
        assertEq(pool.canaryId(), 1);
        assertEq(pool.admin(), admin);
        assertEq(pool.msgMode(), PQAuth.MODE_RAW);
        assertEq(pool.premiumRateBps(), 2_000);
        assertEq(pool.cooldown(), 120);
        assertEq(pool.claimWindow(), 1 hours);
    }

    function test_constructor_requiresAdminKey() public {
        CoverPool.Config memory c = testConfig();
        c.admin = nobody;
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQKeyNotRegistered.selector, nobody));
        new CoverPool(c);
    }

    function test_constructor_rejectsBadConfig() public {
        CoverPool.Config memory c;
        c = testConfig();
        c.minDuration = 0;
        vm.expectRevert(CoverPool.BadConfig.selector);
        new CoverPool(c);
        c = testConfig();
        c.minDuration = c.maxDuration + 1;
        vm.expectRevert(CoverPool.BadConfig.selector);
        new CoverPool(c);
        c = testConfig();
        c.bountyBps = 10_001;
        vm.expectRevert(CoverPool.BadConfig.selector);
        new CoverPool(c);
        c = testConfig();
        c.premiumRateBps = c.maxRateBps + 1;
        vm.expectRevert(CoverPool.BadConfig.selector);
        new CoverPool(c);
        c = testConfig();
        c.maxRateBps = 10_001;
        c.premiumRateBps = 0;
        vm.expectRevert(CoverPool.BadConfig.selector);
        new CoverPool(c);
        c = testConfig();
        c.msgMode = 2;
        vm.expectRevert(CoverPool.BadConfig.selector);
        new CoverPool(c);
        c = testConfig();
        c.minDeposit = 0;
        vm.expectRevert(CoverPool.BadConfig.selector);
        new CoverPool(c);
        c = testConfig();
        c.canaryId = 2;
        vm.expectRevert(CoverPool.BadConfig.selector);
        new CoverPool(c);
        c = testConfig();
        c.registry = address(0);
        vm.expectRevert(CoverPool.ZeroAddress.selector);
        new CoverPool(c);
        c = testConfig();
        c.admin = address(0);
        vm.expectRevert(CoverPool.ZeroAddress.selector);
        new CoverPool(c);
    }

    // ================================================================ deposit

    function test_deposit_mintsShares() public {
        uint256 s = _deposit(lp1, 10 ether);
        assertEq(s, 10 ether * 1e3); // first deposit: assets * (0 + 1e3) / (0 + 1)
        assertEq(pool.sharesOf(lp1), s);
        assertEq(pool.totalShares(), s);
        assertEq(pool.totalAssets(), 10 ether);
        assertApproxEqAbs(pool.toAssets(s), 10 ether, 1);
        uint256 s2 = _deposit(lp2, 5 ether);
        assertApproxEqRel(s2, s / 2, 1e12);
    }

    function test_deposit_creditsReceiverNotSender() public {
        vm.prank(lp1);
        uint256 s = pool.deposit{value: 1 ether}(lp2);
        assertEq(pool.sharesOf(lp2), s);
        assertEq(pool.sharesOf(lp1), 0);
    }

    function test_deposit_inflationAttack_victimSharesStayFair() public {
        // attacker deposits the minimum, then donates a large amount directly to the pool
        address attacker = lp2;
        _deposit(attacker, 0.01 ether);
        vm.deal(address(pool), address(pool).balance + 100 ether); // forced donation (selfdestruct / coinbase)
        uint256 s = _deposit(lp1, 1 ether);
        assertGt(s, 0);
        // the victim can redeem (almost) their whole deposit
        assertApproxEqRel(pool.toAssets(s), 1 ether, 0.001e18);
    }

    function test_deposit_refusesReceiverWithoutProvenKey() public {
        vm.prank(lp1);
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQKeyNotRegistered.selector, nobody));
        pool.deposit{value: 1 ether}(nobody);
        keyStatus.setKey(nobody, true, 1, fakePubkey(nobody), false);
        vm.prank(lp1);
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQKeyNotProven.selector, nobody));
        pool.deposit{value: 1 ether}(nobody);
    }

    function test_deposit_refusedAfterDeath() public {
        _kill();
        vm.prank(lp1);
        vm.expectRevert(CoverPool.CanaryIsDead.selector);
        pool.deposit{value: 1 ether}(lp1);
    }

    function test_deposit_belowMinimum_refused() public {
        vm.prank(lp1);
        vm.expectRevert(CoverPool.BelowMinDeposit.selector);
        pool.deposit{value: 0.01 ether - 1}(lp1);
    }

    function test_deposit_zeroSharesRefused() public {
        _deposit(lp1, 0.01 ether);
        // a huge donation makes a minimum deposit round to zero shares
        vm.deal(address(pool), 1e40);
        vm.prank(lp2);
        vm.expectRevert(CoverPool.ZeroAmount.selector);
        pool.deposit{value: 0.01 ether}(lp2);
    }

    // ================================================================ premium and capacity

    function test_quotePremium_matchesFormula_roundsUp() public view {
        // 5 QOR for 10 minutes at 20%/yr
        uint256 cover = 5 ether;
        uint64 dur = 600;
        uint256 exact = cover * 2_000 * dur / (365 days * 10_000);
        uint256 q = pool.quotePremium(cover, dur);
        assertTrue(q == exact || q == exact + 1);
        // a case with a remainder must round up
        assertEq(pool.quotePremium(1, 60), 1);
    }

    function testFuzz_quotePremium_ceil(uint96 cover, uint32 duration) public view {
        uint256 num = uint256(cover) * 2_000 * duration;
        uint256 den = 365 days * 10_000;
        uint256 expected = num / den + (num % den == 0 ? 0 : 1);
        assertEq(pool.quotePremium(cover, duration), expected);
    }

    function test_buyCover_wrongPremium_revertsWithExpected() public {
        _deposit(lp1, 10 ether);
        uint256 premium = pool.quotePremium(1 ether, 600);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(CoverPool.WrongPremium.selector, premium));
        pool.buyCover{value: premium + 1}(buyer, 1 ether, 600, bytes32(0));
    }

    function test_buyCover_createsPolicy() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 600);
        (address owner, uint128 cover, uint64 start, uint64 expiry, bool released, bool paid, bytes32 note) =
            pool.policies(id);
        assertEq(owner, buyer);
        assertEq(cover, 5 ether);
        assertEq(start, block.timestamp);
        assertEq(expiry, block.timestamp + 600);
        assertFalse(released);
        assertFalse(paid);
        assertEq(note, bytes32(0));
        assertEq(pool.activeCover(), 5 ether);
        assertEq(pool.policiesCount(), 1);
    }

    function test_buyCover_storesNoteHash() public {
        _deposit(lp1, 10 ether);
        uint256 premium = pool.quotePremium(1 ether, 600);
        vm.prank(buyer);
        uint256 id = pool.buyCover{value: premium}(buyer, 1 ether, 600, keccak256("note"));
        (,,,,,, bytes32 note) = pool.policies(id);
        assertEq(note, keccak256("note"));
    }

    /// @dev Largest cover c with activeCover(0) + c <= pool balance after its own premium, i.e. c <= bal + premium(c).
    function _maxCover(uint64 dur) internal view returns (uint256 lo) {
        uint256 bal = address(pool).balance - pool.activeCover();
        lo = bal;
        uint256 hi = bal * 2;
        while (hi - lo > 1) {
            uint256 mid = (lo + hi) / 2;
            if (mid <= bal + pool.quotePremium(mid, dur)) lo = mid;
            else hi = mid;
        }
    }

    function test_capacity_upToFreeCapital_thenOneWeiMoreReverts() public {
        _deposit(lp1, 10 ether);
        uint64 dur = 600;
        uint256 maxCover = _maxCover(dur);
        uint256 pOver = pool.quotePremium(maxCover + 1, dur);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(CoverPool.NoCapacity.selector, 10 ether + pOver));
        pool.buyCover{value: pOver}(buyer, maxCover + 1, dur, bytes32(0));
        _buy(buyer, maxCover, dur);
        assertEq(pool.activeCover(), maxCover);
        assertLe(pool.freeAssets(), 1);
    }

    function test_buyCover_badDuration() public {
        _deposit(lp1, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(CoverPool.BadDuration.selector);
        pool.buyCover{value: 0}(buyer, 1 ether, 59, bytes32(0));
        uint256 p = pool.quotePremium(1 ether, 30 days + 1);
        vm.prank(buyer);
        vm.expectRevert(CoverPool.BadDuration.selector);
        pool.buyCover{value: p}(buyer, 1 ether, 30 days + 1, bytes32(0));
    }

    function test_buyCover_zeroOrHugeCover() public {
        _deposit(lp1, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(CoverPool.ZeroAmount.selector);
        pool.buyCover{value: 0}(buyer, 0, 600, bytes32(0));
        vm.prank(buyer);
        vm.expectRevert(CoverPool.ZeroAmount.selector);
        pool.buyCover{value: 0}(buyer, uint256(type(uint128).max) + 1, 600, bytes32(0));
    }

    function test_buyCover_ownerNeedsProvenKey() public {
        _deposit(lp1, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQKeyNotRegistered.selector, nobody));
        pool.buyCover{value: 0}(nobody, 1 ether, 600, bytes32(0));
    }

    function test_buyCover_impossibleAfterDeath() public {
        _deposit(lp1, 10 ether);
        _kill();
        vm.prank(buyer);
        vm.expectRevert(CoverPool.CanaryIsDead.selector);
        pool.buyCover{value: 0}(buyer, 1 ether, 600, bytes32(0));
    }

    // ================================================================ withdraw

    function test_requestWithdraw_locksShares() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 id = _request(lp1, s / 2);
        assertEq(pool.lockedShares(lp1), s / 2);
        (address owner, uint128 shares, uint64 unlockAt, bool closed) = pool.requests(id);
        assertEq(owner, lp1);
        assertEq(shares, s / 2);
        assertEq(unlockAt, block.timestamp + 120);
        assertFalse(closed);
        assertEq(pool.nonces(lp1), 1);
        assertEq(pool.requestsCount(), 1);
    }

    function test_requestWithdraw_cannotLockMoreThanFree() public {
        uint256 s = _deposit(lp1, 10 ether);
        _request(lp1, s / 2);
        uint256 dl = _dl();
        uint256 tooMany = s / 2 + 1;
        bytes memory sig = _sig(lp1, pool.REQUEST_WITHDRAW(), lp1, dl, keccak256(abi.encode(tooMany)));
        vm.expectRevert(CoverPool.NotEnoughShares.selector);
        pool.requestWithdraw(lp1, tooMany, dl, sig);
        vm.expectRevert(CoverPool.ZeroAmount.selector);
        pool.requestWithdraw(lp1, 0, dl, sig);
    }

    function test_requestWithdraw_needsOwnersSignature() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 dl = _dl();
        bytes memory sig = _sig(lp2, pool.REQUEST_WITHDRAW(), lp1, dl, keccak256(abi.encode(s))); // lp2 signs
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        pool.requestWithdraw(lp1, s, dl, sig);
    }

    function test_executeWithdraw_beforeCooldown_reverts() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 id = _request(lp1, s);
        uint256 dl = _dl();
        bytes memory sig = _sig(lp1, pool.EXECUTE_WITHDRAW(), lp1, dl, keccak256(abi.encode(id, lp1)));
        vm.expectRevert(abi.encodeWithSelector(CoverPool.CooldownActive.selector, uint64(block.timestamp + 120)));
        pool.executeWithdraw(lp1, id, payable(lp1), dl, sig);
    }

    function test_executeWithdraw_afterCooldown_paysChosenRecipient() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 id = _request(lp1, s / 2);
        vm.warp(block.timestamp + 120);
        address recipient = makeAddr("fresh");
        uint256 assets = _execute(lp1, id, recipient);
        assertApproxEqAbs(assets, 5 ether, 1);
        assertEq(recipient.balance, assets);
        assertEq(pool.sharesOf(lp1), s - s / 2);
        assertEq(pool.lockedShares(lp1), 0);
        (,,, bool closed) = pool.requests(id);
        assertTrue(closed);
        // a closed request cannot be executed again
        uint256 dl = _dl();
        bytes memory sig = _sig(lp1, pool.EXECUTE_WITHDRAW(), lp1, dl, keccak256(abi.encode(id, recipient)));
        vm.expectRevert(CoverPool.RequestClosed.selector);
        pool.executeWithdraw(lp1, id, payable(recipient), dl, sig);
    }

    function test_executeWithdraw_recipientIsBoundBySignature() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 id = _request(lp1, s);
        vm.warp(block.timestamp + 120);
        uint256 dl = _dl();
        bytes memory sig = _sig(lp1, pool.EXECUTE_WITHDRAW(), lp1, dl, keccak256(abi.encode(id, lp1)));
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        pool.executeWithdraw(lp1, id, payable(makeAddr("thief")), dl, sig);
        vm.expectRevert(CoverPool.ZeroAddress.selector);
        pool.executeWithdraw(lp1, id, payable(address(0)), dl, sig);
    }

    function test_cancelWithdraw_unlocks() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 id = _request(lp1, s);
        _cancel(lp1, id);
        assertEq(pool.lockedShares(lp1), 0);
        (,,, bool closed) = pool.requests(id);
        assertTrue(closed);
        // can request again
        _request(lp1, s);
    }

    function test_cannotTouchAnotherOwnersRequest() public {
        uint256 s = _deposit(lp1, 10 ether);
        _deposit(lp2, 10 ether);
        uint256 id = _request(lp1, s);
        vm.warp(block.timestamp + 120);
        uint256 dl = _dl();
        bytes memory sig = _sig(lp2, pool.EXECUTE_WITHDRAW(), lp2, dl, keccak256(abi.encode(id, lp2)));
        vm.expectRevert(CoverPool.NotRequestOwner.selector);
        pool.executeWithdraw(lp2, id, payable(lp2), dl, sig);
        sig = _sig(lp2, pool.CANCEL_WITHDRAW(), lp2, dl, keccak256(abi.encode(id)));
        vm.expectRevert(CoverPool.NotRequestOwner.selector);
        pool.cancelWithdraw(lp2, id, dl, sig);
        vm.expectRevert(CoverPool.UnknownId.selector);
        pool.cancelWithdraw(lp2, 99, dl, sig);
    }

    function test_executeWithdraw_limitedByFreeCapital() public {
        uint256 s = _deposit(lp1, 10 ether);
        _buy(buyer, 8 ether, 1 days);
        uint256 id = _request(lp1, s);
        vm.warp(block.timestamp + 120);
        uint256 assets = pool.toAssets(s);
        uint256 free = pool.freeAssets();
        assertLt(free, assets);
        uint256 dl = _dl();
        bytes memory sig = _sig(lp1, pool.EXECUTE_WITHDRAW(), lp1, dl, keccak256(abi.encode(id, lp1)));
        vm.expectRevert(abi.encodeWithSelector(CoverPool.InsufficientFreeCapital.selector, assets, free));
        pool.executeWithdraw(lp1, id, payable(lp1), dl, sig);
        // a smaller request that fits in free capital works
        _cancel(lp1, id);
        uint256 small = pool.toShares(free) * 99 / 100;
        uint256 id2 = _request(lp1, small);
        vm.warp(block.timestamp + 120);
        _execute(lp1, id2, lp1);
        assertGe(address(pool).balance, pool.activeCover());
    }

    function test_frontRunning_deathDuringCooldown_lpGetsOnlyNetAssets() public {
        uint256 s1 = _deposit(lp1, 10 ether);
        _deposit(lp2, 10 ether);
        _buy(buyer, 5 ether, 1 days);
        uint256 id = _request(lp1, s1); // lp1 sees trouble coming and requests everything
        _kill(); // canary dies during the cooldown
        vm.warp(block.timestamp + 120);
        uint256 bal = address(pool).balance;
        uint256 expected = pool.toAssets(s1);
        // LPs own only assets minus liabilities: lp1 holds ~half the shares
        assertApproxEqRel(expected, (bal - 5 ether) / 2, 1e12);
        uint256 got = _execute(lp1, id, lp1);
        assertEq(got, expected);
        // the buyer's cover is still fully backed
        assertGe(address(pool).balance, pool.activeCover());
        _claim(buyer, 0, buyer);
    }

    // ================================================================ expiry

    function test_expire_releasesCapacity() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 600);
        vm.expectRevert(CoverPool.NotEligible.selector);
        pool.expire(id);
        vm.warp(block.timestamp + 600);
        vm.prank(nobody);
        pool.expire(id);
        assertEq(pool.activeCover(), 0);
        vm.expectRevert(CoverPool.AlreadyReleased.selector);
        pool.expire(id);
        vm.expectRevert(CoverPool.UnknownId.selector);
        pool.expire(7);
    }

    function test_expire_afterDeath_onlyForPoliciesExpiredBeforeDeath() public {
        _deposit(lp1, 10 ether);
        uint256 early = _buy(buyer, 1 ether, 60);
        uint256 late = _buy(buyer, 1 ether, 1 days);
        vm.warp(block.timestamp + 120);
        _kill();
        pool.expire(early); // expired before death: fine
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(CoverPool.NotEligible.selector);
        pool.expire(late); // active at death: claimable, not expirable
    }

    function test_expire_paidPolicy_reverts() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 1 ether, 600);
        _kill();
        _claim(buyer, id, buyer);
        vm.warp(block.timestamp + 600);
        vm.expectRevert(CoverPool.AlreadyPaid.selector);
        pool.expire(id);
    }

    // ================================================================ payout

    function test_claimPayout_paysExactCoverToSignedRecipient() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 600);
        _kill();
        address recipient = makeAddr("freshRecipient");
        uint256 amount = _claim(buyer, id, recipient);
        assertEq(amount, 5 ether);
        assertEq(recipient.balance, 5 ether);
        assertEq(pool.activeCover(), 0);
        (,,,, bool released, bool paid,) = pool.policies(id);
        assertTrue(paid);
        assertFalse(released);
    }

    function test_claimPayout_doubleClaim_reverts() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 600);
        _kill();
        _claim(buyer, id, buyer);
        uint256 dl = _dl();
        bytes memory sig = _claimSig(buyer, id, buyer, dl);
        vm.expectRevert(CoverPool.AlreadyPaid.selector);
        pool.claimPayout(id, payable(buyer), dl, sig);
    }

    function test_claimPayout_replayOfSameSignature_reverts() public {
        _deposit(lp1, 10 ether);
        uint256 a = _buy(buyer, 1 ether, 600);
        uint256 b = _buy(buyer, 1 ether, 600);
        _kill();
        uint256 dl = _dl();
        bytes memory sig = _claimSig(buyer, a, buyer, dl);
        pool.claimPayout(a, payable(buyer), dl, sig);
        // nonce moved on: the old signature is invalid for anything else
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        pool.claimPayout(b, payable(buyer), dl, sig);
    }

    function test_claimPayout_cannotBeRedirected() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 600);
        _kill();
        uint256 dl = _dl();
        bytes memory sig = _claimSig(buyer, id, makeAddr("A"), dl);
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        pool.claimPayout(id, payable(makeAddr("B")), dl, sig);
        vm.expectRevert(CoverPool.ZeroAddress.selector);
        pool.claimPayout(id, payable(address(0)), dl, sig);
    }

    function test_claimPayout_onlyPolicyOwnersKey() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 600);
        _kill();
        uint256 dl = _dl();
        // lp2 signs a digest for buyer's policy with lp2's key → rejected
        bytes memory sig = _sig(lp2, pool.CLAIM_PAYOUT(), buyer, dl, keccak256(abi.encode(id, lp2)));
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        pool.claimPayout(id, payable(lp2), dl, sig);
    }

    function test_claimPayout_whileAlive_reverts() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 600);
        uint256 dl = _dl();
        bytes memory sig = _claimSig(buyer, id, buyer, dl);
        vm.expectRevert(CoverPool.CanaryAlive.selector);
        pool.claimPayout(id, payable(buyer), dl, sig);
    }

    function test_claimPayout_afterWindow_reverts() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 600);
        _kill();
        vm.warp(block.timestamp + 1 hours + 1);
        uint256 dl = _dl();
        bytes memory sig = _claimSig(buyer, id, buyer, dl);
        vm.expectRevert(CoverPool.ClaimWindowClosed.selector);
        pool.claimPayout(id, payable(buyer), dl, sig);
    }

    function test_claimPayout_atWindowEdge_succeeds() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 2 hours);
        _kill();
        vm.warp(block.timestamp + 1 hours);
        _claim(buyer, id, buyer);
    }

    function test_claimPayout_policyExpiredBeforeDeath_notEligible() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 60);
        vm.warp(block.timestamp + 60); // expiry == now; death at expiry is NOT covered (deadAt < expiry required)
        _kill();
        uint256 dl = _dl();
        bytes memory sig = _claimSig(buyer, id, buyer, dl);
        vm.expectRevert(CoverPool.NotEligible.selector);
        pool.claimPayout(id, payable(buyer), dl, sig);
    }

    function test_claimPayout_releasedPolicy_reverts() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 60);
        vm.warp(block.timestamp + 60);
        pool.expire(id);
        _kill();
        uint256 dl = _dl();
        bytes memory sig = _claimSig(buyer, id, buyer, dl);
        vm.expectRevert(CoverPool.AlreadyReleased.selector);
        pool.claimPayout(id, payable(buyer), dl, sig);
    }

    function test_claimPayout_unknownPolicy_reverts() public {
        _kill();
        vm.expectRevert(CoverPool.UnknownId.selector);
        pool.claimPayout(3, payable(buyer), _dl(), new bytes(4627));
    }

    function test_claimPayout_failedTransfer_reverts() public {
        _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 5 ether, 600);
        _kill();
        address bad = address(new RejectingReceiver());
        uint256 dl = _dl();
        bytes memory sig = _claimSig(buyer, id, bad, dl);
        vm.expectRevert(CoverPool.TransferFailed.selector);
        pool.claimPayout(id, payable(bad), dl, sig);
    }

    // ================================================================ bounty

    function test_bounty_paidOnceToReporter_cappedAndFromFreeCapital() public {
        _deposit(lp1, 200 ether);
        _buy(buyer, 50 ether, 1 days);
        _kill();
        uint256 bal = address(pool).balance;
        vm.prank(nobody);
        uint256 amount = pool.claimBounty();
        assertEq(amount, 1 ether); // 1% of ~200 = 2 > cap 1
        assertEq(reporter.balance, 1 ether);
        assertEq(address(pool).balance, bal - 1 ether);
        assertGe(address(pool).balance, pool.activeCover());
        vm.expectRevert(CoverPool.BountyAlreadyPaid.selector);
        pool.claimBounty();
        _claim(buyer, 0, buyer); // payouts remain fully funded
    }

    function test_bounty_bpsBelowCap() public {
        _deposit(lp1, 10 ether);
        _kill();
        assertEq(pool.claimBounty(), 0.1 ether); // 1% of 10
    }

    function test_bounty_limitedToFreeAssets() public {
        _deposit(lp1, 10 ether);
        // fill capacity completely so free assets ~0
        uint64 dur = 600;
        _buy(buyer, _maxCover(dur), dur);
        uint256 free = pool.freeAssets();
        _kill();
        assertEq(pool.claimBounty(), free);
        assertGe(address(pool).balance, pool.activeCover());
    }

    function test_bounty_whileAlive_reverts() public {
        vm.expectRevert(CoverPool.CanaryAlive.selector);
        pool.claimBounty();
    }

    // ================================================================ settlement

    function test_finalize_beforeWindow_reverts_thenReleases() public {
        uint256 s = _deposit(lp1, 10 ether);
        _buy(buyer, 5 ether, 1 days);
        vm.expectRevert(CoverPool.CanaryAlive.selector);
        pool.finalizeAfterClaimWindow();
        _kill();
        vm.expectRevert(CoverPool.ClaimWindowOpen.selector);
        pool.finalizeAfterClaimWindow();
        vm.warp(block.timestamp + 1 hours + 1);
        pool.finalizeAfterClaimWindow();
        assertTrue(pool.settled());
        assertEq(pool.activeCover(), 0);
        vm.expectRevert(CoverPool.AlreadySettled.selector);
        pool.finalizeAfterClaimWindow();
        // LPs can now withdraw everything
        uint256 id = _request(lp1, s);
        vm.warp(block.timestamp + 120);
        uint256 got = _execute(lp1, id, lp1);
        assertApproxEqAbs(got, address(pool).balance + got, 1e4);
        assertLt(address(pool).balance, 1e4); // only virtual-offset dust remains
        // nothing can be expired or claimed after settlement
        vm.expectRevert(CoverPool.AlreadySettled.selector);
        pool.expire(0);
        uint256 dl = _dl();
        bytes memory sig = _claimSig(buyer, 0, buyer, dl);
        vm.expectRevert(CoverPool.AlreadySettled.selector);
        pool.claimPayout(0, payable(buyer), dl, sig);
    }

    // ================================================================ admin

    function test_admin_setRate_needsAdminSignature() public {
        uint256 dl = _dl();
        bytes memory sig = _sig(admin, pool.SET_RATE(), admin, dl, keccak256(abi.encode(uint256(300))));
        vm.prank(nobody); // anyone may submit; authority is the signature
        pool.setPremiumRate(300, dl, sig);
        assertEq(pool.premiumRateBps(), 300);
        assertEq(pool.nonces(admin), 1);
    }

    function test_admin_nonAdminSignature_fails() public {
        uint256 dl = _dl();
        bytes memory sig = _sig(lp1, pool.SET_RATE(), admin, dl, keccak256(abi.encode(uint256(300))));
        vm.expectRevert(PQAuth.PQBadSignature.selector);
        pool.setPremiumRate(300, dl, sig);
    }

    function test_admin_rateAboveMax_reverts() public {
        uint256 dl = _dl();
        bytes memory sig = _sig(admin, pool.SET_RATE(), admin, dl, keccak256(abi.encode(uint256(5_001))));
        vm.expectRevert(CoverPool.RateTooHigh.selector);
        pool.setPremiumRate(5_001, dl, sig);
    }

    function test_admin_pause_blocksBuyCoverOnly() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 policy = _buy(buyer, 2 ether, 600);
        uint256 dl = _dl();
        bytes memory sig = _sig(admin, pool.SET_PAUSED(), admin, dl, keccak256(abi.encode(true)));
        pool.setPaused(true, dl, sig);
        assertTrue(pool.paused());
        uint256 premium = pool.quotePremium(1 ether, 600);
        vm.prank(buyer);
        vm.expectRevert(CoverPool.Paused.selector);
        pool.buyCover{value: premium}(buyer, 1 ether, 600, bytes32(0));
        // deposits, withdrawals and claims still work
        _deposit(lp2, 1 ether);
        uint256 id = _request(lp1, s / 4);
        vm.warp(block.timestamp + 120);
        _execute(lp1, id, lp1);
        _kill();
        _claim(buyer, policy, buyer);
        // unpause
        dl = _dl();
        sig = _sig(admin, pool.SET_PAUSED(), admin, dl, keccak256(abi.encode(false)));
        pool.setPaused(false, dl, sig);
        assertFalse(pool.paused());
    }

    // ================================================================ digest view

    function test_actionDigest_matchesPQAuthDigestAtCurrentNonce() public {
        uint256 dl = 1767225600;
        bytes32 ph = keccak256(abi.encode(uint256(42), address(0xbEEF)));
        assertEq(
            pool.actionDigest(pool.CLAIM_PAYOUT(), buyer, dl, ph),
            PQAuth.digest(address(pool), keccak256("CLAIM_PAYOUT"), buyer, 0, dl, ph)
        );
        _deposit(buyer, 1 ether);
        _request(buyer, 1);
        assertEq(
            pool.actionDigest(pool.CLAIM_PAYOUT(), buyer, dl, ph),
            PQAuth.digest(address(pool), keccak256("CLAIM_PAYOUT"), buyer, 1, dl, ph)
        );
    }

    function test_actionConstants() public view {
        assertEq(pool.REQUEST_WITHDRAW(), keccak256("REQUEST_WITHDRAW"));
        assertEq(pool.CANCEL_WITHDRAW(), keccak256("CANCEL_WITHDRAW"));
        assertEq(pool.EXECUTE_WITHDRAW(), keccak256("EXECUTE_WITHDRAW"));
        assertEq(pool.CLAIM_PAYOUT(), keccak256("CLAIM_PAYOUT"));
        assertEq(pool.SET_RATE(), keccak256("SET_RATE"));
        assertEq(pool.SET_PAUSED(), keccak256("SET_PAUSED"));
    }

    function test_views_netAndFreeAssets() public {
        _deposit(lp1, 10 ether);
        _buy(buyer, 4 ether, 600);
        uint256 bal = address(pool).balance;
        assertEq(pool.netAssets(), bal);
        assertEq(pool.freeAssets(), bal - 4 ether);
        (bool dead,) = pool.isDead();
        assertFalse(dead);
        _kill();
        assertEq(pool.netAssets(), bal - 4 ether);
        (dead,) = pool.isDead();
        assertTrue(dead);
    }

    // ================================================================ fail closed

    function test_failClosed_everyAuthorisedFunctionReverts() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 id = _buy(buyer, 1 ether, 600);
        uint256 rid = _request(lp1, s / 2);
        uint256 dl = _dl();
        bytes memory reqSig = _sig(lp1, pool.REQUEST_WITHDRAW(), lp1, dl, keccak256(abi.encode(uint256(1))));
        bytes memory cancelSig = _sig(lp1, pool.CANCEL_WITHDRAW(), lp1, dl, keccak256(abi.encode(rid)));
        bytes memory rateSig = _sig(admin, pool.SET_RATE(), admin, dl, keccak256(abi.encode(uint256(1))));
        bytes memory pauseSig = _sig(admin, pool.SET_PAUSED(), admin, dl, keccak256(abi.encode(true)));
        vm.warp(block.timestamp + 120);
        bytes memory execSig = _sig(lp1, pool.EXECUTE_WITHDRAW(), lp1, dl, keccak256(abi.encode(rid, lp1)));
        _kill();
        bytes memory claimSig = _claimSig(buyer, id, buyer, dl);

        _removePrecompiles();
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        pool.requestWithdraw(lp1, 1, dl, reqSig);
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        pool.cancelWithdraw(lp1, rid, dl, cancelSig);
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        pool.executeWithdraw(lp1, rid, payable(lp1), dl, execSig);
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        pool.claimPayout(id, payable(buyer), dl, claimSig);
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        pool.setPremiumRate(1, dl, rateSig);
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        pool.setPaused(true, dl, pauseSig);
    }

    function test_failClosed_depositAndBuyRefuseWithoutPrecompile() public {
        _deposit(lp1, 10 ether);
        _removePrecompiles();
        vm.prank(lp2);
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        pool.deposit{value: 1 ether}(lp2);
        uint256 premium = pool.quotePremium(1 ether, 600);
        vm.prank(buyer);
        vm.expectRevert(PQAuth.PQPrecompileUnavailable.selector);
        pool.buyCover{value: premium}(buyer, 1 ether, 600, bytes32(0));
    }

    function test_expiredDeadline_reverts() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 dl = _dl();
        bytes memory sig = _sig(lp1, pool.REQUEST_WITHDRAW(), lp1, dl, keccak256(abi.encode(s)));
        vm.warp(dl + 1);
        vm.expectRevert(abi.encodeWithSelector(PQAuth.PQExpired.selector, dl));
        pool.requestWithdraw(lp1, s, dl, sig);
    }

    // ================================================================ reentrancy

    function test_reentrancy_executeWithdraw_blocked() public {
        uint256 s = _deposit(lp1, 10 ether);
        uint256 a = _request(lp1, s / 2);
        uint256 b = _request(lp1, s / 4);
        vm.warp(block.timestamp + 120);
        Reenterer evil = new Reenterer(pool);
        // pre-sign the inner call for request b (nonce after the outer call is consumed)
        uint256 dl = _dl();
        bytes32 inner = PQAuth.digest(
            address(pool),
            pool.EXECUTE_WITHDRAW(),
            lp1,
            pool.nonces(lp1) + 1,
            dl,
            keccak256(abi.encode(b, address(evil)))
        );
        evil.arm(abi.encodeCall(CoverPool.executeWithdraw, (lp1, b, payable(address(evil)), dl, pqSign(lp1, inner))));
        bytes memory sig = _sig(lp1, pool.EXECUTE_WITHDRAW(), lp1, dl, keccak256(abi.encode(a, address(evil))));
        vm.expectRevert(CoverPool.TransferFailed.selector);
        pool.executeWithdraw(lp1, a, payable(address(evil)), dl, sig);
    }

    function test_reentrancy_claimPayout_blocked() public {
        _deposit(lp1, 10 ether);
        uint256 a = _buy(buyer, 1 ether, 600);
        uint256 b = _buy(buyer, 1 ether, 600);
        _kill();
        Reenterer evil = new Reenterer(pool);
        uint256 dl = _dl();
        bytes32 inner = PQAuth.digest(
            address(pool),
            pool.CLAIM_PAYOUT(),
            buyer,
            pool.nonces(buyer) + 1,
            dl,
            keccak256(abi.encode(b, address(evil)))
        );
        evil.arm(abi.encodeCall(CoverPool.claimPayout, (b, payable(address(evil)), dl, pqSign(buyer, inner))));
        bytes memory sig = _claimSig(buyer, a, address(evil), dl);
        vm.expectRevert(CoverPool.TransferFailed.selector);
        pool.claimPayout(a, payable(address(evil)), dl, sig);
        // nothing moved
        assertEq(pool.activeCover(), 2 ether);
    }
}
