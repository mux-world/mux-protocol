// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

uint256 constant DEX_UNISWAP = 0;
uint256 constant DEX_CURVE = 1;

struct DexSpotConfiguration {
    uint8 dexId;
    uint8 dexType;
    uint32 dexWeight;
    uint8[] assetIds;
    uint32[] assetWeightInDex;
    uint256[] totalSpotInDex;
}

struct DexRegistration {
    address adapter;
    bool disabled;
    uint32 slippage;
}

struct DexData {
    bytes config;
    mapping(bytes32 => bytes32) states;
}

struct PluginData {
    mapping(bytes32 => bytes32) states;
}

struct CallContext {
    uint8 dexId;
}
