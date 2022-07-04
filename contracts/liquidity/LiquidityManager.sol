// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../interfaces/ILiquidityPool.sol";
import "../libraries/LibUtils.sol";

import "./Types.sol";
import "./Storage.sol";
import "./AssetManager.sol";
import "./Admin.sol";
import "./ExtensionProxy.sol";

/**
 * @title LiquidityManager provides funds management and bridging services.
 */
contract LiquidityManager is Storage, AssetManager, DexWrapper, Admin, ExtensionProxy {
    receive() external payable {}

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

    function getPool() public view returns (address) {
        return _pool;
    }

    function getVault() public view returns (address) {
        return _vault;
    }

    function getAssetBroker() public view returns (address) {
        return _assetBroker;
    }

    function isHandler(address handler) public view returns (bool) {
        return _handlers[handler];
    }

    function getAllDexSpotConfiguration() external returns (DexSpotConfiguration[] memory configs) {
        uint256 n = _dexSpotConfigs.length - 1;
        if (n == 0) {
            return configs;
        }
        configs = new DexSpotConfiguration[](n);
        for (uint8 dexId = 1; dexId <= n; dexId++) {
            configs[dexId - 1] = _getDexSpotConfiguration(dexId);
        }
        return configs;
    }

    function getDexSpotConfiguration(uint8 dexId) external returns (DexSpotConfiguration memory config) {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        config = _getDexSpotConfiguration(dexId);
    }

    function getDexLiquidity(uint8 dexId) external returns (uint256[] memory liquidities, uint256 lpBalance) {
        lpBalance = getDexLpBalance(dexId);
        liquidities = getDexSpotAmounts(dexId, lpBalance);
    }

    function getDexAdapterConfig(uint8 dexId) external view returns (bytes memory config) {
        config = _dexData[dexId].config;
    }

    function getDexAdapterState(uint8 dexId, bytes32 key) external view returns (bytes32 state) {
        state = _dexData[dexId].states[key];
    }

    function getDexAdapter(uint8 dexId) external view returns (DexRegistration memory registration) {
        registration = _dexAdapters[dexId];
    }

    function _getDexSpotConfiguration(uint8 dexId) internal returns (DexSpotConfiguration memory config) {
        config = _dexSpotConfigs[dexId];
        if (config.dexType == DEX_CURVE) {
            uint256[] memory amounts = getDexTotalSpotAmounts(dexId);
            config.totalSpotInDex = amounts;
        }
    }
}
