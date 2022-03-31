// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

struct LiquidityPoolStorage {
    address orderBook;
    address mlp;
    address liquidityManager;
    address weth;
    // Funding rate formular
    //
    // ^ fr           ______ limit
    // |            /
    // |          /
    // |        /
    // |______/ base
    // |    .
    // |  .
    // |.
    // +-------------------> %util
    // slot
    uint128 shortCumulativeFunding;
    uint32 shortFundingBaseRate8H; // 1e5
    uint32 shortFundingLimitRate8H; // 1e5
    uint32 fundingInterval; // 1e0
    uint32 lastFundingTime; // 1e0
    // slot
    uint32 reserved1; // TODO: remove me
    Asset[] assets;
    mapping(bytes32 => SubAccount) accounts;
    mapping(address => LiquidityLockRemoveMe) reserved2; // TODO: remove me
    address mlpTimeLock; // TODO: move me
    uint96 reserved3; // TODO: remove me
    // slot
    uint96 mlpPriceLowerBound; // safeguard against mlp price attacks
    uint96 mlpPriceUpperBound; // safeguard against mlp price attacks
    bytes32[50] _gap;
}

struct Asset {
    // slot
    bytes32 symbol;
    // slot
    address tokenAddress;
    uint8 id;
    uint8 decimals;
    bool isStable;
    bool isTradable;
    bool isOpenable;
    bool isShortable;
    bool useStableTokenForProfit;
    uint40 _flagsPadding;
    // slot
    uint32 initialMarginRate; // 1e5
    uint32 maintenanceMarginRate; // 1e5
    uint32 minProfitRate; // 1e5
    uint32 minProfitTime; // 1e0
    uint32 positionFeeRate; // 1e5
    // note: 24 bits remaining
    // slot
    address referenceOracle;
    uint32 referenceDeviation; // 1e5
    uint8 referenceOracleType;
    // note: 56 bits remaining
    // slot
    uint128 tokenBalance; // erc20.balanceOf
    uint128 _tokenBalancePadding; // note: not used
    // slot
    uint128 collectedFee;
    uint96 spotLiquidity;
    // slot
    uint96 maxLongPositionSize;
    uint96 totalLongPosition;
    // slot
    uint96 averageLongPrice;
    uint96 maxShortPositionSize;
    // slot
    uint96 totalShortPosition;
    uint96 averageShortPrice;
    // slot, less used
    address muxTokenAddress;
    uint32 spotWeight; // 1e0
    uint32 longFundingBaseRate8H; // 1e5
    uint32 longFundingLimitRate8H; // 1e5
    // slot
    uint128 longCumulativeFunding;
    // note: 128 bits remaining
}

struct SubAccount {
    // slot
    uint96 collateral;
    uint96 size;
    uint32 lastIncreasedTime;
    // slot
    uint96 entryPrice;
    uint128 entryFunding;
}

// TODO: remove me
struct LiquidityLockRemoveMe {
    uint32 lastAddedTime; // 1e0
    uint96 pendingMLP;
}

enum ReferenceOracleType {
    None,
    Chainlink
}
