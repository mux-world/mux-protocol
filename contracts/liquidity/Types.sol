// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

uint256 constant DEX_UNISWAP = 0;
uint256 constant DEX_CURVE = 1;

struct DexSpotConfiguration {
    uint8 dexId;
    uint8 dexType; // 0 = default (uni), 1 = curve
    uint32 dexWeight;
    uint8[] assetIds;
    uint32[] assetWeightInDex;
    uint256[] totalSpotInDex;
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
