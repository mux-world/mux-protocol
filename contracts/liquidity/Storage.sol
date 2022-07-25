// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./Types.sol";
import "../components/SafeOwnableUpgradeable.sol";

// prev storages:
// contract CrossStorage {
//     address internal _vault;
//     address internal _pool;
//     DexSpotConfiguration[] internal _dexSpotConfigs;
//     mapping(bytes32 => bytes32[]) internal _moduleData;
//     bytes32[50] private __moduleGaps;
// }

// contract Storage is CrossStorage {
//     mapping(bytes32 => ModuleInfo) internal _moduleInfos;
//     mapping(bytes32 => CallRegistration) internal _genericRoutes; // method -> call
//     mapping(uint8 => mapping(bytes32 => CallRegistration)) internal _dexRoutes; // dexId -> method -> call
//     mapping(address => bool) internal _externalAccessors;
//     bytes32[50] private __gaps;
// }

contract PlaceHolder {
    bytes32[200] private __deprecated;
}

contract Storage is PlaceHolder, Initializable, SafeOwnableUpgradeable {
    // base properties
    address internal _vault;
    address internal _pool;

    DexSpotConfiguration[] internal _dexSpotConfigs;
    // address => isAllowed
    mapping(address => bool) internal _handlers;
    CallContext internal _dexContext;
    // dexId => Context
    mapping(uint8 => DexData) internal _dexData;
    // assetId => address
    mapping(uint8 => address) internal _tokenCache;
    // dexId => dexRegistration
    mapping(uint8 => DexRegistration) internal _dexAdapters;
    // sig => callee
    mapping(bytes4 => address) internal _plugins;
    mapping(string => PluginData) internal _pluginData;

    address internal _maintainer;
    // reserves
    bytes32[49] private __gaps;
}
