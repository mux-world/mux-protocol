// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/ILiquidityPool.sol";
import "../libraries/LibUtils.sol";
import "./Types.sol";
import "./Storage.sol";
import "./ModuleCall.sol";
import "./Admin.sol";

/**
 * @title LiquidityManager provides funds management and bridging services.
 */
contract LiquidityManager is Storage, Initializable, SafeOwnableUpgradeable, ModuleCall, Admin {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event CallMethod(uint8 dexId, bytes32 methodId, bytes params);
    bytes32 constant GET_TOTAL_SPOT_AMOUNTS_METHOD_ID =
        0x676574546f74616c53706f74416d6f756e747300000000000000000000000000; // toBytes32("getDynamicWeights")

    /**
     * @notice Initialize the LiquidityManager.
     */
    function initialize(address vault_, address pool_) external initializer {
        __SafeOwnable_init();
        _vault = vault_;
        _pool = pool_;
        // 0 for placeHolder
        _dexSpotConfigs.push();
    }

    function vault() public view returns (address) {
        return _vault;
    }

    function readStates(bytes32 moduleId) external view returns (bytes32[] memory) {
        return _moduleData[moduleId];
    }

    function hasGenericCall(bytes32 methodId) external view returns (bool) {
        return _hasGenericCall(methodId);
    }

    function hasDexCall(uint8 dexId, bytes32 methodId) external view returns (bool) {
        return _hasDexCall(dexId, methodId);
    }

    function getDexSpotConfiguration(uint8 dexId) external returns (DexSpotConfiguration memory) {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        return _getDexSpotConfiguration(dexId);
    }

    function getAllDexSpotConfiguration() external returns (DexSpotConfiguration[] memory) {
        DexSpotConfiguration[] memory results = new DexSpotConfiguration[](_dexSpotConfigs.length - 1);
        for (uint256 i = 0; i < _dexSpotConfigs.length - 1; i++) {
            uint8 dexId = uint8(i + 1);
            results[i] = _getDexSpotConfiguration(dexId);
        }
        return results;
    }

    function _getDexSpotConfiguration(uint8 dexId) internal returns (DexSpotConfiguration memory) {
        DexSpotConfiguration memory result = _dexSpotConfigs[dexId];
        if (result.dexType == DEX_CURVE) {
            result.totalSpotInDex = abi.decode(_dexCall(dexId, GET_TOTAL_SPOT_AMOUNTS_METHOD_ID, ""), (uint256[]));
        }
        return result;
    }

    function getModuleInfo(bytes32 moduleId) external view returns (ModuleInfo memory) {
        return _moduleInfos[moduleId];
    }

    function callGenericModule(bytes32 methodId, bytes memory params) external returns (bytes memory) {
        require(msg.sender == owner() || _externalAccessors[msg.sender], "FMS"); // forbidden message sender
        emit CallMethod(0, methodId, params);
        return _genericCall(methodId, params);
    }

    function callDexModule(
        uint8 dexId,
        bytes32 methodId,
        bytes memory params
    ) external returns (bytes memory) {
        require(msg.sender == owner() || _externalAccessors[msg.sender], "FMS"); // forbidden message sender
        emit CallMethod(dexId, methodId, params);
        return _dexCall(dexId, methodId, params);
    }
}
