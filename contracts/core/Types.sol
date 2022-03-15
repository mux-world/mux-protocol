// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

struct LiquidityPoolStorage {
    // config
    // slot
    address orderBook;
    uint32 fundingInterval; // 1e0 // TODO: miss Getter
    uint32 liquidityLockPeriod; // 1e0
    // slot
    address mlp;
    address liquidityManager;
    FundingConfiguration shortFundingConfiguration;
    // state
    FundingState shortFunding;
    Asset[] assets;
    mapping(bytes32 => SubAccount) accounts;
    mapping(address => uint32) liquidityLocks;
    bytes32[50] _gap;
}

/**
 * @notice Funding rate formular
 *
 * ^ fr           ______ limit
 * |            /
 * |          /
 * |        /
 * |______/ base
 * |    .
 * |  .
 * |.
 * +-------------------> %util
 */
struct FundingConfiguration {
    uint32 baseRate8H; // 1e5
    uint32 limitRate8H; // 1e5
}

struct FundingState {
    uint128 cumulativeFunding;
    uint32 lastFundingTime; // 1e0
}

struct Asset {
    // configuration
    bytes32 symbol;
    uint8 id;
    uint8 decimals;
    bool isStable;
    bool isTradable;
    bool isOpenable;
    bool isShortable;
    bool useStableTokenForProfit;
    address tokenAddress;
    address muxTokenAddress;
    uint32 initialMarginRate; // 1e5
    uint32 maintenanceMarginRate; // 1e5
    uint32 positionFeeRate; // 1e5
    uint32 minProfitRate; // 1e5
    uint32 minProfitTime; // 1e0
    uint96 maxLongPositionSize;
    uint96 maxShortPositionSize;
    uint32 spotWeight; // 1e0
    uint8 backupOracleType;
    address backupOracle;
    FundingConfiguration longFundingConfiguration;
    // states
    FundingState longFunding;
    uint128 tokenBalance; // erc20.balanceOf
    uint96 liquidityBalance;
    uint96 totalLongPosition;
    uint96 averageLongPrice;
    uint96 totalShortPosition;
    uint96 averageShortPrice;
    uint128 collectedFee;
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

enum AdminParamsType {
    AddAsset,
    SetAssetParams,
    SetAssetFlags,
    SetFundingParams,
    SetFundingInterval,
    SetAddresses,
    SetLiquidityLockPeriod,
    WithdrawLiquidity,
    DepositLiquidity
}
