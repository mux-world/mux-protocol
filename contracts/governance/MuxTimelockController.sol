// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract MuxTimelockController is TimelockController {
    using Address for address;

    address public emergencyCall;

    event SetEmergencyFunctions(address emergencyFunctions);
    event CallEmergencyFunction(address path, bytes callData, bytes returnData);

    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors) {}

    function setEmergencyCall(address _emergencyCall) external {
        require(emergencyCall != _emergencyCall, "CHG");
        require(msg.sender == address(this), "S!T");
        emergencyCall = _emergencyCall;
        emit SetEmergencyFunctions(_emergencyCall);
    }

    function executeEmergencyCall(bytes calldata callData) external {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "Sender must have EXECUTOR_ROLE");
        require(emergencyCall != address(0), "EmergencyCall not set");
        bytes memory returnData = emergencyCall.functionDelegateCall(callData);
        emit CallEmergencyFunction(emergencyCall, callData, returnData);
    }
}
