// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../../interfaces/IDexAdapter.sol";

import "../AssetManager.sol";

abstract contract DexAdapter is AssetManager, IDexAdapter {
    event TransferFeeToVault(address token, address vault, uint256 amount);

    function _dexId() internal view returns (uint8) {
        return _dexContext.dexId;
    }

    function _getAssetCount() internal view returns (uint256) {
        return _dexSpotConfigs[_dexId()].assetIds.length;
    }

    function _getConfig() internal view returns (bytes memory) {
        return _dexData[_dexId()].config;
    }

    function _getState(bytes32 key) internal view returns (bytes32) {
        return _dexData[_dexContext.dexId].states[key];
    }

    function _getStateAsUint256(bytes32 key) internal view returns (uint256) {
        return uint256(_dexData[_dexContext.dexId].states[key]);
    }

    function _getStateAsAddress(bytes32 key) internal view returns (address) {
        return address(bytes20(_dexData[_dexContext.dexId].states[key]));
    }

    function _setState(bytes32 key, bytes32 value) internal {
        _dexData[_dexContext.dexId].states[key] = value;
    }

    function _setStateAsUint256(bytes32 key, uint256 value) internal {
        _dexData[_dexContext.dexId].states[key] = bytes32(value);
    }

    function _incStateAsUint256(bytes32 key, uint256 incValue) internal {
        _setStateAsUint256(key, _getStateAsUint256(key) + incValue);
    }

    function _setStateAsAddress(bytes32 key, address value) internal {
        _dexData[_dexContext.dexId].states[key] = bytes32(bytes20(value));
    }

    function _getDexTokens() internal view returns (address[] memory) {
        return _getDexTokens(_dexContext.dexId);
    }
}
