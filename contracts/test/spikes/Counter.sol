// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

/// @notice Throwaway contract for SPIKE S2 (deploy route + scoped-window refusal target).
contract Counter {
    uint256 public number;

    event Incremented(address indexed by, uint256 number);

    /// @notice Increment the counter.
    function increment() external {
        number += 1;
        emit Incremented(msg.sender, number);
    }
}
