// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {CanaryRegistry} from "../src/CanaryRegistry.sol";
import {CoverPool} from "../src/CoverPool.sol";
import {PQAuth} from "../src/lib/PQAuth.sol";
import {PQTestBase} from "./PQTestBase.sol";

/// @notice Shared fixture: a registry (real + test canary) and a test-parameter pool on the test canary.
abstract contract CoverPoolBase is PQTestBase {
    CanaryRegistry internal reg;
    CoverPool internal pool;

    uint256 internal constant TEST_CANARY_KEY = 0xC0FFEE;
    address internal admin = makeAddr("admin");
    address internal lp1 = makeAddr("lp1");
    address internal lp2 = makeAddr("lp2");
    address internal buyer = makeAddr("buyer");
    address internal reporter = makeAddr("reporter");
    address internal nobody = makeAddr("nobody"); // no PQ key

    function setUp() public virtual {
        vm.warp(1_800_000_000);
        _installPrecompiles();
        registerKey(admin);
        registerKey(lp1);
        registerKey(lp2);
        registerKey(buyer);
        reg = new CanaryRegistry(_canaries());
        pool = new CoverPool(testConfig());
        vm.deal(lp1, 1_000 ether);
        vm.deal(lp2, 1_000 ether);
        vm.deal(buyer, 1_000 ether);
    }

    function _canaries() internal pure returns (CanaryRegistry.Canary[] memory c) {
        c = new CanaryRegistry.Canary[](2);
        c[0] = CanaryRegistry.Canary(
            address(0x1234567890123456789012345678901234567890),
            false,
            0,
            address(0),
            "Canary #1",
            "QoreChain Canary 2026 #1",
            "CANARY-V1-QORECHAIN_XMD:SHA-256_SSWU_RO_"
        );
        c[1] = CanaryRegistry.Canary(vm.addr(TEST_CANARY_KEY), true, 0, address(0), "TEST canary", "", "");
    }

    /// @dev Test-pool parameters from plan 03 (rate 20%/yr).
    function testConfig() internal view returns (CoverPool.Config memory) {
        return CoverPool.Config({
            registry: address(reg),
            canaryId: 1,
            admin: admin,
            msgMode: PQAuth.MODE_RAW,
            minDuration: 60,
            maxDuration: 30 days,
            cooldown: 120,
            claimWindow: 1 hours,
            bountyBps: 100,
            bountyCap: 1 ether,
            minDeposit: 0.01 ether,
            maxRateBps: 5_000,
            premiumRateBps: 2_000
        });
    }

    // ---- actions

    function _deposit(address who, uint256 amount) internal returns (uint256) {
        vm.prank(who);
        return pool.deposit{value: amount}(who);
    }

    function _buy(address who, uint256 cover, uint64 duration) internal returns (uint256) {
        uint256 premium = pool.quotePremium(cover, duration);
        vm.prank(who);
        return pool.buyCover{value: premium}(who, cover, duration, bytes32(0));
    }

    function _kill() internal {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_CANARY_KEY, reg.breakDigest(1, reporter));
        reg.reportBreak(1, reporter, v, r, s);
    }

    function _sig(address signer, bytes32 action, address owner, uint256 deadline, bytes32 paramsHash)
        internal
        view
        returns (bytes memory)
    {
        return pqSign(signer, pool.actionDigest(action, owner, deadline, paramsHash));
    }

    function _dl() internal view returns (uint256) {
        return block.timestamp + 600;
    }

    function _request(address owner, uint256 shares) internal returns (uint256) {
        uint256 dl = _dl();
        bytes memory sig = _sig(owner, pool.REQUEST_WITHDRAW(), owner, dl, keccak256(abi.encode(shares)));
        return pool.requestWithdraw(owner, shares, dl, sig);
    }

    function _cancel(address owner, uint256 id) internal {
        uint256 dl = _dl();
        bytes memory sig = _sig(owner, pool.CANCEL_WITHDRAW(), owner, dl, keccak256(abi.encode(id)));
        pool.cancelWithdraw(owner, id, dl, sig);
    }

    function _execute(address owner, uint256 id, address recipient) internal returns (uint256) {
        uint256 dl = _dl();
        bytes memory sig = _sig(owner, pool.EXECUTE_WITHDRAW(), owner, dl, keccak256(abi.encode(id, recipient)));
        return pool.executeWithdraw(owner, id, payable(recipient), dl, sig);
    }

    function _claimSig(address owner, uint256 policyId, address recipient, uint256 dl)
        internal
        view
        returns (bytes memory)
    {
        return _sig(owner, pool.CLAIM_PAYOUT(), owner, dl, keccak256(abi.encode(policyId, recipient)));
    }

    function _claim(address owner, uint256 policyId, address recipient) internal returns (uint256) {
        uint256 dl = _dl();
        bytes memory sig = _claimSig(owner, policyId, recipient, dl);
        return pool.claimPayout(policyId, payable(recipient), dl, sig);
    }
}
