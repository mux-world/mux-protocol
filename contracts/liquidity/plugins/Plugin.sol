// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../../interfaces/IPlugin.sol";

import "../AssetManager.sol";

abstract contract Plugin is AssetManager, IPlugin {
    function name() public pure virtual returns (string memory);

    function _getState(bytes32 key) internal view returns (bytes32) {
        return _pluginData[name()].states[key];
    }

    function _setState(bytes32 key, bytes32 value) internal {
        _pluginData[name()].states[key] = value;
    }

    function _getStateAsUint256(bytes32 key) internal view returns (uint256) {
        return uint256(_getState(key));
    }

    function _getStateAsAddress(bytes32 key) internal view returns (address) {
        return address(bytes20(_getState(key)));
    }

    function _setStateAsUint256(bytes32 key, uint256 value) internal {
        _setState(key, bytes32(value));
    }

    function _setStateAsAddress(bytes32 key, address value) internal {
        _setState(key, bytes32(bytes20(value)));
    }

    function _incStateAsUint256(bytes32 key, uint256 incValue) internal {
        _setStateAsUint256(key, _getStateAsUint256(key) + incValue);
    }
}
