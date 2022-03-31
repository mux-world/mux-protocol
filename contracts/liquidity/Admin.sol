// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../interfaces/IModule.sol";

import "./Storage.sol";
import "./ModuleCall.sol";

contract Admin is Storage, Initializable, SafeOwnableUpgradeable, ModuleCall {
    using AddressUpgradeable for address;

    event AddExternalAccessor(address indexed accessor);
    event RemoveExternalAccessor(address indexed accessor);
    event AddDex(uint8 indexed dexId, string name, uint32 dexWeight, uint8[] assetIds, uint32[] assetWeightInDex);
    event SetDexWeight(uint8 indexed dexId, uint32 dexWeight);
    event InstallModule(bytes32 indexed moduleId, address module, bytes32[] methodIds, bytes4[] selectors);
    event UninstallModule(bytes32 indexed moduleId, address module, bytes32[] methods);

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
     * @param name The name of dex for user to distinguish between the configurations.
     * @param assetIds The array represents the category of assets to add to the dex.
     * @param assetWeightInDex The array represents the weight of each asset added to the dex as liquidity.
     *
     */
    function addDexSpotConfiguration(
        string memory name,
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
                name: name,
                dexId: dexId,
                dexWeight: dexWeight,
                assetIds: assetIds,
                assetWeightInDex: assetWeightInDex
            })
        );
        emit AddDex(dexId, name, dexWeight, assetIds, assetWeightInDex);
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
        emit SetDexWeight(dexId, dexWeight);
    }

    /**
     * @notice Install a generic module. A generic module implements basic method to extend 
               the abilities of `LiquidityManager`, eg: transfer funds and transfer across chain.
               The module must implement the `IModule` interface (contracts/interfaces/IModule.sol).
     * @param module The address of the module to install.
     */
    function installGenericModule(address module) external onlyOwner {
        require(module.isContract(), "MNC"); // the module is not a contract
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
            _moduleData[moduleId] = initialStates;
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
     */
    function installDexModule(uint8 dexId, address module) external onlyOwner {
        require(dexId != 0 && dexId < _dexSpotConfigs.length, "LST"); // the asset is not LiSTed
        require(module.isContract(), "MNC"); // the module is not a contract
        (
            bytes32 moduleId,
            bytes32[] memory methodIds,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        ) = _getModuleInfo(module);
        require(!_hasModule(moduleId), "MHI"); // module has been installed
        uint256 length = methodIds.length;
        for (uint256 i = 0; i < length; i++) {
            // has dex id as prefix
            require(!_hasDexCall(dexId, methodIds[i]), "MLR"); // method is already registered
            _dexRoutes[dexId][methodIds[i]] = CallRegistration(module, selectors[i]);
            _moduleData[moduleId] = initialStates;
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
        ModuleInfo storage module = _moduleInfos[moduleId];
        emit UninstallModule(moduleId, module.path, methodIds);
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
            // must not installed
            require(!_hasModule(moduleId_), "MHI"); // module has installed
            try IModule(module).meta() returns (
                bytes32[] memory methodIds_,
                bytes4[] memory selectors_,
                bytes32[] memory initialStates_
            ) {
                require(methodIds_.length != 0, "MTY"); // empty module
                require(methodIds_.length == selectors_.length, "IMM"); // invalid module meta info
                moduleId = moduleId_;
                methodIds = methodIds_;
                selectors = selectors_;
                initialStates = initialStates_;
            } catch {
                revert("IMM"); // invalid module meta info
            }
        } catch {
            revert("IMM"); // invalid module meta info
        }
    }
}
