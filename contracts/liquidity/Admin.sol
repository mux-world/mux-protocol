// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../interfaces/IModule.sol";
import "../interfaces/IDexModule.sol";

import "./Storage.sol";
import "./ModuleCall.sol";

contract Admin is Storage, Initializable, SafeOwnableUpgradeable, ModuleCall {
    using AddressUpgradeable for address;

    bytes32 constant METHOD_GET_LP_BALANCE = 0x6765744c7042616c616e63650000000000000000000000000000000000000000; // "getLpBalance" to bytes32

    event AddExternalAccessor(address indexed accessor);
    event RemoveExternalAccessor(address indexed accessor);
    event AddDex(uint8 indexed dexId, uint8 dexType, uint32 dexWeight, uint8[] assetIds, uint32[] assetWeightInDex);
    event SetDexWeight(uint8 indexed dexId, uint32 dexWeight, uint32[] assetWeightInDex);
    event SetAssetIds(uint8 indexed dexId, uint8[] assetIds);
    event InstallModule(bytes32 indexed moduleId, address module, bytes32[] methodIds, bytes4[] selectors);
    event UninstallModule(bytes32 indexed moduleId, address module, bytes32[] methods);
    event ClearStates(bytes32 indexed moduleId);

    function setVault(address newVault) external onlyOwner {
        require(newVault != address(0), "ZVA"); // zero vault address
        require(newVault != _vault, "DVA"); // duplicated vault address
        _vault = newVault;
    }

    function addExternalAccessor(address accessor) external onlyOwner {
        require(!_externalAccessors[accessor], "DEA"); // duplicated external accessor
        _externalAccessors[accessor] = true;
        emit AddExternalAccessor(accessor);
    }

    function removeExternalAccessor(address accessor) external onlyOwner {
        require(_externalAccessors[accessor], "ANE"); // accessor not exists
        _externalAccessors[accessor] = false;
        emit RemoveExternalAccessor(accessor);
    }

    /**
     * @notice Add a configuration for dex.
     *         Each configuration [dex, assets0, asset1, ...] represents a combination of dex pool address and assets categories.
     *         Once added, the combination cannot be modified except the weights.
     * @param dexType The type of dex, 0 = uniswap, 1 = curve
     * @param assetIds The array represents the category of assets to add to the dex.
     * @param assetWeightInDex The array represents the weight of each asset added to the dex as liquidity.
     *
     */
    function addDexSpotConfiguration(
        uint8 dexType,
        uint32 dexWeight,
        uint8[] calldata assetIds,
        uint32[] calldata assetWeightInDex
    ) external onlyOwner {
        require(_dexSpotConfigs.length <= 256, "FLL"); // the array is FuLL
        require(assetIds.length > 0, "MTY"); // argument array is eMpTY
        require(assetIds.length == assetWeightInDex.length, "LEN"); // LENgth of 2 arguments does not match
        uint8 dexId = uint8(_dexSpotConfigs.length);
        _dexSpotConfigs.push(
            DexSpotConfiguration({
                dexId: dexId,
                dexType: dexType,
                dexWeight: dexWeight,
                assetIds: assetIds,
                assetWeightInDex: assetWeightInDex,
                totalSpotInDex: new uint256[](assetIds.length)
            })
        );
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
        DexSpotConfiguration storage config = _dexSpotConfigs[dexId];
        config.dexWeight = dexWeight;
        config.assetWeightInDex = assetWeightInDex;
        emit SetDexWeight(dexId, dexWeight, assetWeightInDex);
    }

    /**
     * @notice Modify the weight of a dex configuration. Only can be modified when lp balance is zero or no module.
     * @param dexId The id of the dex.
     * @param assetIds The new ids of the dex.
     */
    function setAssetIds(uint8 dexId, uint8[] memory assetIds) external onlyOwner {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        if (_hasDexCall(dexId, METHOD_GET_LP_BALANCE)) {
            require(_getLpBalance(dexId) == 0, "LNZ"); // lp-balance is not zero
        }
        _dexSpotConfigs[dexId].assetIds = assetIds;
        emit SetAssetIds(dexId, assetIds);
    }

    /**
     * @notice Install a generic module. A generic module implements basic method to extend 
               the abilities of `LiquidityManager`, eg: transfer funds and transfer across chain.
               The module must implement the `IModule` interface (contracts/interfaces/IModule.sol).
     * @param module The address of the module to install.
     * @param overwriteStates Overwrite the initial states of module.
     */
    function installGenericModule(address module, bool overwriteStates) external onlyOwner {
        // require(module.isContract(), "MNC"); // the module is not a contract
        (
            bytes32 moduleId,
            bytes32[] memory methodIds,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        ) = _getModuleInfo(module);
        // cannot install multiple times, must uninstall first
        require(!_hasModule(moduleId), "MHI"); // module has been installed
        for (uint256 i = 0; i < methodIds.length; i++) {
            require(!_hasGenericCall(methodIds[i]), "MLR"); // method is already registered
            _genericRoutes[methodIds[i]] = CallRegistration(module, selectors[i]);
            if (overwriteStates || _moduleData[moduleId].length == 0) {
                _moduleData[moduleId] = initialStates;
            }
        }
        _moduleInfos[moduleId] = ModuleInfo({
            id: moduleId,
            path: module,
            isDexModule: false,
            dexId: 0,
            methodIds: methodIds
        });
        emit InstallModule(moduleId, module, methodIds, selectors);
    }

    /**
     * @notice Install a dex module. A dex module implements interfaces to operate the dex (add/removeLiquidity or farming).
     * @param dexId The id of the dex.
     * @param module The address of the module to install.
     * @param overwriteStates Overwrite the initial states of module.
     */
    function installDexModule(
        uint8 dexId,
        address module,
        bool overwriteStates
    ) external onlyOwner {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        // require(module.isContract(), "MNC"); // the module is not a contract

        // todo: +validate before final deployment
        // IModule(module).validate(_pool, address(this), dexId);
        (
            bytes32 moduleId,
            bytes32[] memory methodIds,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        ) = _getModuleInfo(module);
        require(!_hasModule(moduleId), "MHI"); // module has been installed
        require(checkTokenAddresses(dexId, module), "TNM"); // token address not match

        uint256 length = methodIds.length;
        for (uint256 i = 0; i < length; i++) {
            // has dex id as prefix
            require(!_hasDexCall(dexId, methodIds[i]), "MLR"); // method is already registered
            _dexRoutes[dexId][methodIds[i]] = CallRegistration(module, selectors[i]);
        }
        // init or override
        if (overwriteStates || _moduleData[moduleId].length == 0) {
            _moduleData[moduleId] = initialStates;
        } else if (_moduleData[moduleId].length < initialStates.length) {
            // extend to proper size
            uint256 toExtend = initialStates.length - _moduleData[moduleId].length;
            for (uint256 i = 0; i < toExtend; i++) {
                _moduleData[moduleId].push(bytes32(0));
            }
        }
        _moduleInfos[moduleId] = ModuleInfo({
            id: moduleId,
            path: module,
            isDexModule: true,
            dexId: dexId,
            methodIds: methodIds
        });
        emit InstallModule(moduleId, module, methodIds, selectors);
    }

    /**
     * @notice Uninstall a generic module or a dex module.
     * @param moduleId The id of the module to install.
     */
    function clearStates(bytes32 moduleId) external onlyOwner {
        delete _moduleData[moduleId];
        emit ClearStates(moduleId);
    }

    /**
     * @notice Uninstall a generic module or a dex module.
     * @param moduleId The id of the module to install.
     */
    function setStates(bytes32 moduleId, bytes32[] memory states) external onlyOwner {
        _moduleData[moduleId] = states;
        emit ClearStates(moduleId);
    }

    /**
     * @notice Uninstall a generic module or a dex module.
     * @param moduleId The id of the module to install.
     */
    function uninstallModule(bytes32 moduleId) external onlyOwner {
        require(_hasModule(moduleId), "MNI"); // module is not installed
        ModuleInfo storage moduleInfo = _moduleInfos[moduleId];
        bytes32[] storage methodIds = moduleInfo.methodIds;
        for (uint256 i = 0; i < methodIds.length; i++) {
            if (moduleInfo.isDexModule) {
                delete _dexRoutes[moduleInfo.dexId][methodIds[i]];
            } else {
                delete _genericRoutes[methodIds[i]];
            }
        }
        emit UninstallModule(moduleId, moduleInfo.path, methodIds);
        delete _moduleInfos[moduleId];
    }

    function _getModuleInfo(address module)
        internal
        view
        returns (
            bytes32 moduleId,
            bytes32[] memory methodIds,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        )
    {
        try IModule(module).id() returns (bytes32 moduleId_) {
            moduleId = moduleId_;
        } catch {
            revert("IVI"); // invalid module meta info
        }
        require(!_hasModule(moduleId), "MHI"); // module has installed
        // must not installed
        try IModule(module).meta() returns (
            bytes32[] memory methodIds_,
            bytes4[] memory selectors_,
            bytes32[] memory initialStates_
        ) {
            require(methodIds_.length != 0, "MTY"); // empty module
            require(methodIds_.length == selectors_.length, "IMM"); // invalid module meta info
            methodIds = methodIds_;
            selectors = selectors_;
            initialStates = initialStates_;
        } catch {
            revert("IVM"); // invalid module meta info
        }
    }

    function checkTokenAddresses(uint8 dexId, address module) public view returns (bool) {
        address[] memory tokens;
        try IDexModule(module).tokens() returns (bool needCheck_, address[] memory tokens_) {
            if (!needCheck_) {
                return true;
            }
            tokens = tokens_;
        } catch {
            return false;
        }
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        uint256 length = tokens.length;
        DexSpotConfiguration memory config = _dexSpotConfigs[dexId];
        for (uint256 i = 0; i < length; i++) {
            if (_getTokenAddr(config.assetIds[i]) != tokens[i]) {
                return false;
            }
        }
        return true;
    }

    function _getTokenAddr(uint8 assetId) internal view returns (address) {
        return ILiquidityPool(_pool).getAssetAddress(assetId);
    }

    function _getLpBalance(uint8 dexId) internal returns (uint256) {
        bytes memory result = _dexCall(dexId, METHOD_GET_LP_BALANCE, "");
        require(result.length == 32, "ILR"); // invalid length of return data
        return abi.decode(result, (uint256));
    }
}
