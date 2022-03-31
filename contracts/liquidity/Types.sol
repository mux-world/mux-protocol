// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

struct DexSpotConfiguration {
    string name;
    uint8 dexId;
    uint32 dexWeight;
    uint8[] assetIds;
    uint32[] assetWeightInDex;
}

struct ModuleInfo {
    bytes32 id;
    address path;
    bool isDexModule;
    uint8 dexId;
    bytes32[] methodIds;
}

struct CallRegistration {
    address callee;
    bytes4 selector;
}

struct CallContext {
    bytes32 methodId;
    bytes params;
    uint8 dexId;
}
