// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

struct DexSpotConfiguration {
    uint8 dexId;
    uint32 dexWeight;
    uint8[] assetIds;
    uint32[] assetWeightInDex;
    address lpToken;
}

struct DexConnectorConfiguration {
    address connector;
    bytes dexData;
    uint32 liquiditySlippage;
}
