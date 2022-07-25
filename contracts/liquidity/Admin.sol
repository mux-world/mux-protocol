// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/IPlugin.sol";
import "./AssetManager.sol";
import "./DexWrapper.sol";

contract Admin is AssetManager, DexWrapper {
    using AddressUpgradeable for address;

    uint32 constant DEFAULT_SLIPPAGE = 1000; // 1%

    event SetHandler(address handler, bool enable);
    event AddDex(uint8 dexId, uint8 dexType, uint32 dexWeight, uint8[] assetIds, uint32[] assetWeightInDex);
    event SetDexWeight(uint8 dexId, uint32 dexWeight, uint32[] assetWeightInDex);
    event SetAssetIds(uint8 dexId, uint8[] assetIds);
    event SetDexAdapter(uint8 dexId, address entrypoint, bytes initialData);
    event SetDexWrapperEnable(uint8 dexId, bool enable);
    event SetDexSlippage(uint8 dexId, uint32 slippage);
    event SetPlugin(address plugin, bool enable, bytes4[] selectors);
    event SetVault(address previousVault, address newVault);
    event SetPool(address previousVault, address newPool);
    event SetMaintainer(address previousMaintainer, address newMaintainer);

    function setVault(address newVault) external onlyOwner {
        require(newVault != address(0), "ZAD"); // zero address
        require(newVault != _vault, "DUP"); // duplicated
        emit SetVault(_vault, newVault);
        _vault = newVault;
    }

    function setPool(address newPool) external onlyOwner {
        require(newPool != address(0), "ZAD"); // zero address
        require(newPool != _pool, "DUP"); // duplicated
        emit SetPool(_pool, newPool);
        _pool = newPool;
    }

    function setMaintainer(address newMaintainer) external onlyOwner {
        require(newMaintainer != _maintainer, "DUP"); // duplicated
        emit SetMaintainer(_maintainer, newMaintainer);
        _maintainer = newMaintainer;
    }

    function setHandler(address handler, bool enable) external onlyOwner {
        require(_handlers[handler] != enable, "DUP");
        _handlers[handler] = enable;
        emit SetHandler(handler, enable);
    }

    /**
     * @notice Add a configuration for dex.
     *         Each configuration [dex, assets0, asset1, ...] represents a combination of dex pool address and assets categories.
     * @param dexId The name of dex for user to distinguish between the configurations.
     * @param dexType The name of dex for user to distinguish between the configurations.
     * @param dexWeight The name of dex for user to distinguish between the configurations.
     * @param assetIds The array represents the category of assets to add to the dex.
     * @param assetWeightInDex The array represents the weight of each asset added to the dex as liquidity.
     *
     */
    function addDexSpotConfiguration(
        uint8 dexId,
        uint8 dexType,
        uint32 dexWeight,
        uint8[] calldata assetIds,
        uint32[] calldata assetWeightInDex
    ) external onlyOwner {
        require(_dexSpotConfigs.length <= 256, "FLL"); // the array is FuLL
        require(assetIds.length > 0, "MTY"); // argument array is eMpTY
        require(assetIds.length == assetWeightInDex.length, "LEN"); // LENgth of 2 arguments does not match
        require(dexId == _dexSpotConfigs.length, "IDI"); // invalid dex id

        _dexSpotConfigs.push(
            DexSpotConfiguration({
                dexId: dexId,
                dexType: dexType,
                dexWeight: dexWeight,
                assetIds: assetIds,
                assetWeightInDex: assetWeightInDex,
                totalSpotInDex: _makeEmpty(assetIds.length)
            })
        );
        for (uint256 i = 0; i < assetIds.length; i++) {
            _tryGetTokenAddress(assetIds[i]);
        }
        emit AddDex(dexId, dexType, dexWeight, assetIds, assetWeightInDex);
    }

    /**
     * @notice Modify the weight of a dex configuration.
     * @param dexId The id of the dex.
     * @param dexWeight The new weight of the dex.
     */
    function setDexWeight(
        uint8 dexId,
        uint32 dexWeight,
        uint32[] memory assetWeightInDex
    ) external onlyOwner {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        _dexSpotConfigs[dexId].dexWeight = dexWeight;
        _dexSpotConfigs[dexId].assetWeightInDex = assetWeightInDex;
        emit SetDexWeight(dexId, dexWeight, assetWeightInDex);
    }

    function refreshTokenCache(uint8[] memory assetIds) external {
        for (uint256 i = 0; i < assetIds.length; i++) {
            _tokenCache[assetIds[i]] = ILiquidityPool(_pool).getAssetAddress(assetIds[i]);
        }
    }

    /**
     * @notice Modify the weight of a dex configuration. Only can be modified when lp balance is zero or no module.
     * @param dexId The id of the dex.
     * @param assetIds The new ids of the dex.
     */
    function setAssetIds(uint8 dexId, uint8[] memory assetIds) external onlyOwner {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        require(getDexLpBalance(dexId) == 0, "FBD"); // forbidden
        _dexSpotConfigs[dexId].assetIds = assetIds;
        emit SetAssetIds(dexId, assetIds);
    }

    function setDexWrapper(
        uint8 dexId,
        address adapter,
        bytes memory initialData
    ) external onlyOwner {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        _dexAdapters[dexId].adapter = adapter;
        _dexAdapters[dexId].slippage = DEFAULT_SLIPPAGE;
        _initializeAdapter(dexId, initialData);
        emit SetDexAdapter(dexId, adapter, initialData);
    }

    function setDexSlippage(uint8 dexId, uint32 slippage) external onlyOwner {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        require(slippage <= BASE_RATE, "OOR"); // out of range
        _dexAdapters[dexId].slippage = slippage;
        emit SetDexSlippage(dexId, slippage);
    }

    function freezeDexWrapper(uint8 dexId, bool enable) external onlyOwner {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        _dexAdapters[dexId].disabled = !enable;
        emit SetDexWrapperEnable(dexId, enable);
    }

    function setPlugin(address plugin, bool enable) external onlyOwner {
        require(plugin != address(0), "ZPA"); // zero plugin address
        bytes4[] memory selectors;
        try IPlugin(plugin).exports() returns (bytes4[] memory _selectors) {
            selectors = _selectors;
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("SushiFarm::CallUnStakeFail");
        }
        if (enable) {
            for (uint256 i = 0; i < selectors.length; i++) {
                require(_plugins[selectors[i]] == address(0), "PAE"); // plugin already exists
                _plugins[selectors[i]] = plugin;
            }
        } else {
            for (uint256 i = 0; i < selectors.length; i++) {
                require(_plugins[selectors[i]] != address(0), "PNE"); // plugin not exists
                delete _plugins[selectors[i]];
            }
        }
        emit SetPlugin(plugin, enable, selectors);
    }
}
