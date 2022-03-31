// SPDX-License-Identifier: UNLICENSED
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

    function hasGenericCall(bytes32 methodId) external view returns (bool) {
        return _hasGenericCall(methodId);
    }

    function hasDexCall(uint8 dexId, bytes32 methodId) external view returns (bool) {
        return _hasDexCall(dexId, methodId);
    }

    function getDexSpotConfiguration(uint8 dexId) external view returns (DexSpotConfiguration memory) {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        return _dexSpotConfigs[dexId];
    }

    function getAllDexSpotConfiguration() external view returns (DexSpotConfiguration[] memory) {
        DexSpotConfiguration[] memory configs = new DexSpotConfiguration[](_dexSpotConfigs.length - 1);
        for (uint256 i = 0; i < _dexSpotConfigs.length - 1; i++) {
            configs[i] = _dexSpotConfigs[i + 1];
        }
        return configs;
    }

    function getModuleInfo(bytes32 moduleId) external view returns (ModuleInfo memory) {
        return _moduleInfos[moduleId];
    }

    function moduleCall(CallContext memory context) external returns (bytes memory) {
        require(msg.sender == owner() || _externalAccessors[msg.sender], "FMS"); // forbidden message sender
        return _moduleCall(context);
    }

    function batchModuleCall(CallContext[] memory contexts) external returns (bytes[] memory results) {
        require(msg.sender == owner() || _externalAccessors[msg.sender], "FMS"); // forbidden message sender
        uint256 length = contexts.length;
        require(length > 0, "MTY"); // argument array is eMpTY
        results = new bytes[](length);
        for (uint256 i = 0; i < length; i++) {
            results[i] = _moduleCall(contexts[i]);
        }
    }

    function _moduleCall(CallContext memory context) internal returns (bytes memory) {
        if (context.dexId != 0) {
            return _dexCall(context.dexId, context.methodId, context.params);
        } else {
            return _genericCall(context.methodId, context.params);
        }
    }
}
