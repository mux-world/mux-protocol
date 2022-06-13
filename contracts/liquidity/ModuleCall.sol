// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./Storage.sol";

contract ModuleCall is Storage {
    using AddressUpgradeable for address;

    function _hasModule(bytes32 moduleId) public view returns (bool) {
        return _moduleInfos[moduleId].methodIds.length != 0;
    }

    function _hasGenericCall(bytes32 methodId) public view returns (bool) {
        return _genericRoutes[methodId].callee != address(0);
    }

    function _hasDexCall(uint8 dexId, bytes32 methodId) public view returns (bool) {
        return _dexRoutes[dexId][methodId].callee != address(0);
    }

    function _genericCall(bytes32 methodId, bytes memory params) internal returns (bytes memory) {
        return _call(_genericRoutes[methodId], params);
    }

    function _dexCall(
        uint8 dexId,
        bytes32 methodId,
        bytes memory params
    ) internal returns (bytes memory) {
        return _call(_dexRoutes[dexId][methodId], params);
    }

    function _call(CallRegistration storage registration, bytes memory params) internal returns (bytes memory) {
        require(registration.callee != address(0), "MNV");
        // require(registration.callee.isContract(), "T!C");
        (bool success, bytes memory returnData) = registration.callee.delegatecall(
            abi.encodePacked(registration.selector, params)
        );
        return AddressUpgradeable.verifyCallResult(success, returnData, "!DC");
    }
}
