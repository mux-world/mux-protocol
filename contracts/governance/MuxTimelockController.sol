// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract MuxTimelockController is TimelockController {
    using Address for address;

    mapping(address => bool) public quickPaths;
    event AddQuickPath(address indexed path);
    event RemoveQuickPath(address indexed path);
    event ExecuteQuickPath(address indexed path, bytes pluginData);

    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors) {}

    function addQuickPath(address path) external {
        require(!quickPaths[path], "QPE");
        require(msg.sender == address(this), "S!T");
        require(path.isContract(), "P!C");
        quickPaths[path] = true;
        emit AddQuickPath(path);
    }

    function removeQuickPath(address path) external {
        require(quickPaths[path], "QPE");
        require(msg.sender == address(this), "S!T");
        delete quickPaths[path];
        emit RemoveQuickPath(path);
    }

    function executeQuickPath(address path, bytes calldata pluginData) external {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "S!R");
        require(quickPaths[path], "!QP");
        path.functionDelegateCall(pluginData);
        emit ExecuteQuickPath(path, pluginData);
    }
}
