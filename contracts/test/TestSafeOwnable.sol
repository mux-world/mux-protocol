// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../components/SafeOwnable.sol";

contract TestSafeOwnable is SafeOwnable {
    function initialize() external initializer {
        __SafeOwnable_init();
    }

    function foo() external view onlyOwner returns (uint256) {
        return 10000;
    }

    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }
}
