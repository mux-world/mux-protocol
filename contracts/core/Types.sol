// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

struct LiquidityPoolStorage {
    address orderBook;
    address mlp;
    address liquidityManager;
    address weth;
    // slot
    uint128 _reserved1;
    uint32 shortFundingBaseRate8H; // 1e5
    uint32 shortFundingLimitRate8H; // 1e5
    uint32 fundingInterval; // 1e0
    uint32 lastFundingTime; // 1e0
    // slot
    uint32 _reserved2;
    Asset[] assets;
    mapping(bytes32 => SubAccount) accounts;
    mapping(address => bytes32) _reserved3;
    address _reserved4;
    uint96 _reserved5;
    // slot
    uint96 mlpPriceLowerBound; // safeguard against mlp price attacks
    uint96 mlpPriceUpperBound; // safeguard against mlp price attacks
    uint32 liquidityBaseFeeRate; // 1e5
    uint32 liquidityDynamicFeeRate; // 1e5
    bytes32[50] _gap;
}

struct Asset {
    // slot
    bytes32 symbol;
    // slot
    address tokenAddress; // erc20.address
    uint8 id;
    uint8 decimals; // erc20.decimals
    bool isStable; // is a usdt, usdc, ...
    bool isTradable; // allowed to be assetId
    bool isOpenable; // can open position
    bool isShortable; // allow shorting this asset
    bool useStableTokenForProfit; // take profit will get stable coin
    bool isEnabled; // allowed to be assetId and collateralId
    bool isStrictStable; // assetPrice is always 1
    uint24 _flagsPadding;
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
    uint128 _reserved1; // reserved. was tokenBalance
    uint128 _reserved2; // reserved. was tokenBalance padding
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
    address muxTokenAddress; // muxToken.address. all stable coins share the same muxTokenAddress
    uint32 spotWeight; // 1e0
    uint32 longFundingBaseRate8H; // 1e5
    uint32 longFundingLimitRate8H; // 1e5
    // slot
    uint128 longCumulativeFundingRate; // Σ_t fundingRate_t
    uint128 shortCumulativeFunding; // Σ_t fundingRate_t * indexPrice_t
}

struct SubAccount {
    // slot
    uint96 collateral;
    uint96 size;
    uint32 lastIncreasedTime;
    // slot
    uint96 entryPrice;
    uint128 entryFunding; // entry longCumulativeFundingRate for long position. entry shortCumulativeFunding for short position
}

enum ReferenceOracleType {
    None,
    Chainlink
}
