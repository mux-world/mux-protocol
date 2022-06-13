// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../components/SafeOwnable.sol";
import "../components/SafeOwnableUpgradeable.sol";

contract TestSafeOwnableUpgradeable is SafeOwnableUpgradeable {
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

contract TestSafeOwnable is SafeOwnable {
    constructor() SafeOwnable() {}

    function foo() external view onlyOwner returns (uint256) {
        return 10000;
    }

    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }
}
