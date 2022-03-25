// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

enum BridgeProvider {
    None,
    Celer
}

struct DexSpotConfiguration {
    string name;
    uint8 dexId;
    uint32 dexWeight;
    uint8[] assetIds;
    uint32[] assetWeightInDex;
}

struct DexConnectorConfiguration {
    address connector;
    uint32 liquiditySlippage;
}

struct BridgeConfiguration {
    uint256 chainId;
    address bridge;
    address recipient;
    uint128 nonce;
    BridgeProvider provider;
    bytes extraData;
}
