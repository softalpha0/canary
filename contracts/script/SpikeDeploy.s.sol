// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {Counter} from "../test/spikes/Counter.sol";

/// @notice SPIKE S2 route B: does `forge script` deploy cleanly on QoreChain testnet?
contract SpikeDeploy is Script {
    function run() external returns (Counter c) {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        c = new Counter();
        vm.stopBroadcast();
    }
}
