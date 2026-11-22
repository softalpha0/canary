// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

/// @notice Throwaway contract for SPIKE S2/S3: calls both QoreChain PQC precompiles from a contract,
///         with low-level staticcalls and explicit returndata length checks (the PQAuth pattern).
contract PQProbe {
    address internal constant PQC_VERIFY = 0x0000000000000000000000000000000000000a01;
    address internal constant PQC_KEY_STATUS = 0x0000000000000000000000000000000000000a02;

    uint256 public probes;

    event KeyStatus(address indexed account, bool registered, uint8 algorithmId, uint256 pubkeyLength, bool proven);
    event Verified(address indexed caller, bool valid, uint256 gasUsed);

    error PrecompileUnavailable(address precompile, uint256 returndataLength);

    /// @notice Read pqcKeyStatus(account) as a view.
    function keyStatus(address account)
        public
        view
        returns (bool registered, uint8 algorithmId, bytes memory pubkey, bool proven)
    {
        (bool ok, bytes memory ret) = PQC_KEY_STATUS.staticcall(abi.encodeWithSignature("pqcKeyStatus(address)", account));
        if (!ok || ret.length < 128) revert PrecompileUnavailable(PQC_KEY_STATUS, ret.length);
        return abi.decode(ret, (bool, uint8, bytes, bool));
    }

    /// @notice Call pqcVerify as a view.
    function verify(bytes calldata pubkey, bytes calldata sig, bytes calldata message) public view returns (bool) {
        (bool ok, bytes memory ret) =
            PQC_VERIFY.staticcall(abi.encodeWithSignature("pqcVerify(bytes,bytes,bytes)", pubkey, sig, message));
        if (!ok || ret.length < 32) revert PrecompileUnavailable(PQC_VERIFY, ret.length);
        return abi.decode(ret, (bool));
    }

    /// @notice State-changing probe: looks up the caller's registered key, verifies `sig` over `message`
    ///         with it, and emits both results. Used to measure real on-chain gas of a PQ-authorised call.
    function probe(bytes calldata sig, bytes calldata message) external returns (bool valid) {
        uint256 g = gasleft();
        (bool registered, uint8 algo, bytes memory pubkey, bool proven) = keyStatus(msg.sender);
        emit KeyStatus(msg.sender, registered, algo, pubkey.length, proven);
        valid = this.verify(pubkey, sig, message);
        probes += 1;
        emit Verified(msg.sender, valid, g - gasleft());
    }
}
