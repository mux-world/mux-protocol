// SPDX-License-Identifier: MIT
// This file just references TransparentUpgradeableProxy
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

contract MuxTimelock is TimelockControllerUpgradeable {
    function initialize(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) external initializer {
        __TimelockController_init(minDelay, proposers, executors);
    }
}
