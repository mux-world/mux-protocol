// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IOrderBook.sol";
import "../interfaces/ILiquidityManager.sol";

contract Reader {
    struct ChainConfig {
        LiquidityPoolConfig poolConfig;
        AssetConfig[] assetConfigs;
        DexConfig[] dexConfigs;
        uint32 liquidityLockPeriod; // 1e0
    }

    struct ChainState {
        LiquidityPoolState poolState;
        AssetState[] assetStates;
        DexState[] dexStates;
        uint256 lpDeduct; // MLP totalSupply = PRE_MINED - Σ_chains lpDeduct
        uint256 stableDeduct; // debt of stable coins = PRE_MINED - Σ_chains stableDeduct
    }

    struct ChainStorage {
        PoolStorage pool;
        AssetStorage[] assets;
        DexStorage[] dexes;
        uint32 liquidityLockPeriod; // 1e0
        uint256 lpDeduct; // MLP totalSupply = PRE_MINED - Σ_chains lpDeduct
        uint256 stableDeduct; // debt of stable coins = PRE_MINED - Σ_chains stableDeduct
    }

    struct LiquidityPoolConfig {
        uint32 shortFundingBaseRate8H; // 1e5
        uint32 shortFundingLimitRate8H; // 1e5
        uint32 fundingInterval; // 1e0
        uint32 liquidityBaseFeeRate; // 1e5
        uint32 liquidityDynamicFeeRate; // 1e5
        uint96 mlpPriceLowerBound;
        uint96 mlpPriceUpperBound;
        uint32 strictStableDeviation; // 1e5
    }

    struct LiquidityPoolState {
        uint32 lastFundingTime; // 1e0
        uint32 sequence; // 1e0
    }

    struct PoolStorage {
        uint32 shortFundingBaseRate8H; // 1e5
        uint32 shortFundingLimitRate8H; // 1e5
        uint32 fundingInterval; // 1e0
        uint32 liquidityBaseFeeRate; // 1e5
        uint32 liquidityDynamicFeeRate; // 1e5
        uint96 mlpPriceLowerBound;
        uint96 mlpPriceUpperBound;
        uint32 lastFundingTime; // 1e0
        uint32 sequence; // 1e0. note: will be 0 after 0xffffffff
        uint32 strictStableDeviation; // 1e5
    }

    struct AssetConfig {
        bytes32 symbol;
        address tokenAddress;
        address muxTokenAddress;
        uint8 id;
        uint8 decimals;
        bool isStable;
        bool isTradable;
        bool isOpenable;
        bool isShortable;
        bool useStableTokenForProfit;
        bool isEnabled;
        bool isStrictStable;
        uint32 initialMarginRate; // 1e5
        uint32 maintenanceMarginRate; // 1e5
        uint32 positionFeeRate; // 1e5
        uint32 minProfitRate; // 1e5
        uint32 minProfitTime; // 1e0
        uint96 maxLongPositionSize;
        uint96 maxShortPositionSize;
        uint32 spotWeight;
        uint32 longFundingBaseRate8H; // 1e5
        uint32 longFundingLimitRate8H; // 1e5
        uint8 referenceOracleType;
        address referenceOracle;
        uint32 referenceDeviation;
        uint32 halfSpread;
    }

    struct AssetState {
        uint8 id;
        uint128 longCumulativeFundingRate;
        uint128 shortCumulativeFunding;
        uint96 spotLiquidity;
        uint96 totalLongPosition;
        uint96 totalShortPosition;
        uint96 averageLongPrice;
        uint96 averageShortPrice;
        uint96 collectedFee;
        uint256 deduct; // debt of a non-stable coin = PRE_MINED - Σ_chains deduct
    }

    struct AssetStorage {
        bytes32 symbol;
        address tokenAddress;
        address muxTokenAddress;
        uint8 id;
        uint8 decimals;
        bool isStable;
        bool isTradable;
        bool isOpenable;
        bool isShortable;
        bool useStableTokenForProfit;
        bool isEnabled;
        bool isStrictStable;
        uint32 initialMarginRate; // 1e5
        uint32 maintenanceMarginRate; // 1e5
        uint32 positionFeeRate; // 1e5
        uint32 minProfitRate; // 1e5
        uint32 minProfitTime; // 1e0
        uint96 maxLongPositionSize;
        uint96 maxShortPositionSize;
        uint32 spotWeight;
        uint32 longFundingBaseRate8H; // 1e5
        uint32 longFundingLimitRate8H; // 1e5
        uint8 referenceOracleType;
        address referenceOracle;
        uint32 referenceDeviation;
        uint32 halfSpread;
        uint128 longCumulativeFundingRate;
        uint128 shortCumulativeFunding;
        uint96 spotLiquidity;
        uint96 totalLongPosition;
        uint96 totalShortPosition;
        uint96 averageLongPrice;
        uint96 averageShortPrice;
        uint128 collectedFee;
        uint256 deduct; // debt of a non-stable coin = PRE_MINED - Σ_chains deduct
    }

    struct DexConfig {
        uint8 dexId;
        uint8 dexType;
        uint8[] assetIds;
        uint32[] assetWeightInDEX;
        uint32 dexWeight;
        uint256[] totalSpotInDEX;
    }

    struct DexState {
        uint8 dexId;
        uint256 dexLPBalance;
        uint256[] liquidityBalance;
    }

    struct DexStorage {
        uint8 dexId;
        uint8 dexType;
        uint8[] assetIds;
        uint32[] assetWeightInDEX;
        uint256[] totalSpotInDEX;
        uint32 dexWeight;
        uint256 dexLPBalance;
        uint256[] liquidityBalance;
    }

    struct SubAccountState {
        uint96 collateral;
        uint96 size;
        uint32 lastIncreasedTime;
        uint96 entryPrice;
        uint128 entryFunding;
    }

    ILiquidityPool public pool;
    IERC20 public mlp;
    ILiquidityManager public dex;
    IOrderBook public orderBook;
    address[] public deductWhiteList;

    constructor(
        address pool_,
        address mlp_,
        address dex_,
        address orderBook_,
        address[] memory deductWhiteList_ // muxToken in these addresses are also not considered as debt
    ) {
        pool = ILiquidityPool(pool_);
        mlp = IERC20(mlp_);
        dex = ILiquidityManager(dex_);
        orderBook = IOrderBook(orderBook_);
        uint256 listLength = deductWhiteList_.length;
        for (uint256 i = 0; i < listLength; i++) {
            deductWhiteList.push(deductWhiteList_[i]);
        }
    }

    function getChainConfig() public returns (ChainConfig memory chainConfig) {
        // from pool
        (uint32[8] memory u32s, uint96[2] memory u96s) = pool.getLiquidityPoolStorage();
        chainConfig.poolConfig = _convertPoolConfig(u32s, u96s);
        // from assets
        Asset[] memory assets = pool.getAllAssetInfo();
        uint256 assetLength = assets.length;
        chainConfig.assetConfigs = new AssetConfig[](assetLength);
        for (uint256 i = 0; i < assetLength; i++) {
            chainConfig.assetConfigs[i] = _convertAssetConfig(assets[i]);
        }
        // from liquidityManager
        DexSpotConfiguration[] memory dexConfigs = dex.getAllDexSpotConfiguration();
        uint256 dexConfigLength = dexConfigs.length;
        chainConfig.dexConfigs = new DexConfig[](dexConfigLength);
        for (uint256 i = 0; i < dexConfigLength; i++) {
            chainConfig.dexConfigs[i] = _convertDexConfig(dexConfigs[i]);
        }
        // from orderBook
        chainConfig.liquidityLockPeriod = orderBook.liquidityLockPeriod();
    }

    function getChainState() public returns (ChainState memory chainState) {
        // from pool
        (uint32[8] memory u32s, uint96[2] memory u96s) = pool.getLiquidityPoolStorage();
        chainState.poolState = _convertPoolState(u32s, u96s);
        // from assets
        address stableMuxTokenAddress;
        Asset[] memory assets = pool.getAllAssetInfo();
        uint256 assetLength = assets.length;
        chainState.assetStates = new AssetState[](assetLength);
        for (uint256 i = 0; i < assetLength; i++) {
            chainState.assetStates[i] = _convertAssetState(assets[i]);
            if (!assets[i].isStable) {
                chainState.assetStates[i].deduct = getDeduct(assets[i].muxTokenAddress);
            } else {
                stableMuxTokenAddress = assets[i].muxTokenAddress;
            }
        }
        // from liquidityManager
        DexSpotConfiguration[] memory dexConfigs = dex.getAllDexSpotConfiguration();
        uint256 dexConfigLength = dexConfigs.length;
        chainState.dexStates = new DexState[](dexConfigLength);
        for (uint256 i = 0; i < dexConfigLength; i++) {
            uint8 dexId = dexConfigs[i].dexId;
            chainState.dexStates[i].dexId = dexId;
            (uint256[] memory liquidities, uint256 lpBalance) = dex.getDexLiquidity(dexId);
            chainState.dexStates[i].dexLPBalance = lpBalance;
            if (lpBalance == 0) {
                chainState.dexStates[i].liquidityBalance = new uint256[](dexConfigs[i].assetIds.length);
            } else {
                chainState.dexStates[i].liquidityBalance = liquidities;
            }
        }
        // Deduct
        chainState.lpDeduct = getDeduct(address(mlp));
        if (stableMuxTokenAddress != address(0)) {
            chainState.stableDeduct = getDeduct(stableMuxTokenAddress);
        }
    }

    function getChainStorage() public returns (ChainStorage memory chain) {
        // from pool
        (uint32[8] memory u32s, uint96[2] memory u96s) = pool.getLiquidityPoolStorage();
        chain.pool = _convertPoolStorage(u32s, u96s);
        // from assets
        address stableMuxTokenAddress;
        Asset[] memory assets = pool.getAllAssetInfo();
        uint256 assetLength = assets.length;
        chain.assets = new AssetStorage[](assetLength);
        for (uint256 i = 0; i < assetLength; i++) {
            chain.assets[i] = _convertAssetStorage(assets[i]);
            if (!assets[i].isStable) {
                chain.assets[i].deduct = getDeduct(assets[i].muxTokenAddress);
            } else {
                stableMuxTokenAddress = assets[i].muxTokenAddress;
            }
        }
        // from liquidityManager
        DexSpotConfiguration[] memory dexConfigs = dex.getAllDexSpotConfiguration();
        uint256 dexConfigLength = dexConfigs.length;
        chain.dexes = new DexStorage[](dexConfigLength);
        for (uint256 i = 0; i < dexConfigLength; i++) {
            chain.dexes[i] = _convertDexStorage(dexConfigs[i]);
            uint8 dexId = dexConfigs[i].dexId;
            (uint256[] memory liquidities, uint256 lpBalance) = dex.getDexLiquidity(dexId);
            chain.dexes[i].dexLPBalance = lpBalance;
            if (lpBalance == 0) {
                chain.dexes[i].liquidityBalance = new uint256[](dexConfigs[i].assetIds.length);
            } else {
                chain.dexes[i].liquidityBalance = liquidities;
            }
        }
        // from orderBook
        chain.liquidityLockPeriod = orderBook.liquidityLockPeriod();
        // Deduct
        chain.lpDeduct = getDeduct(address(mlp));
        if (stableMuxTokenAddress != address(0)) {
            chain.stableDeduct = getDeduct(stableMuxTokenAddress);
        }
    }

    function getDeduct(address muxToken) internal view returns (uint256 deduct) {
        deduct = IERC20(muxToken).balanceOf(address(pool));
        for (uint256 i = 0; i < deductWhiteList.length; i++) {
            deduct += IERC20(muxToken).balanceOf(deductWhiteList[i]);
        }
        return deduct;
    }

    function getSubAccounts(bytes32[] memory subAccountIds) public view returns (SubAccountState[] memory subAccounts) {
        subAccounts = new SubAccountState[](subAccountIds.length);
        for (uint256 i = 0; i < subAccountIds.length; i++) {
            (uint96 collateral, uint96 size, uint32 lastIncreasedTime, uint96 entryPrice, uint128 entryFunding) = pool
                .getSubAccount(subAccountIds[i]);
            subAccounts[i] = SubAccountState(collateral, size, lastIncreasedTime, entryPrice, entryFunding);
        }
    }

    function getOrders(uint64[] memory orderIds)
        public
        view
        returns (bytes32[3][] memory orders, bool[] memory isExist)
    {
        orders = new bytes32[3][](orderIds.length);
        isExist = new bool[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            (orders[i], isExist[i]) = orderBook.getOrder(orderIds[i]);
        }
    }

    function getSubAccountsAndOrders(bytes32[] memory subAccountIds, uint64[] memory orderIds)
        public
        view
        returns (
            SubAccountState[] memory subAccounts,
            bytes32[3][] memory orders,
            bool[] memory isOrderExist
        )
    {
        subAccounts = new SubAccountState[](subAccountIds.length);
        for (uint256 i = 0; i < subAccountIds.length; i++) {
            (uint96 collateral, uint96 size, uint32 lastIncreasedTime, uint96 entryPrice, uint128 entryFunding) = pool
                .getSubAccount(subAccountIds[i]);
            subAccounts[i] = SubAccountState(collateral, size, lastIncreasedTime, entryPrice, entryFunding);
        }
        orders = new bytes32[3][](orderIds.length);
        isOrderExist = new bool[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            (orders[i], isOrderExist[i]) = orderBook.getOrder(orderIds[i]);
        }
    }

    /**
     * @dev CAUTION: assetsState[i].deduct is NOT calculated. call getChainState instead.
     */
    function getAssetsState(uint8[] memory assetIds) public view returns (AssetState[] memory assetsState) {
        assetsState = new AssetState[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; i++) {
            Asset memory asset = pool.getAssetInfo(assetIds[i]);
            assetsState[i] = _convertAssetState(asset);
        }
    }

    function getErc20Balances(address[] memory tokens, address owner) public view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(owner);
        }
    }

    function _convertPoolConfig(uint32[8] memory u32s, uint96[2] memory u96s)
        internal
        pure
        returns (LiquidityPoolConfig memory c)
    {
        c.shortFundingBaseRate8H = u32s[0];
        c.shortFundingLimitRate8H = u32s[1];
        c.fundingInterval = u32s[3];
        c.liquidityBaseFeeRate = u32s[4];
        c.liquidityDynamicFeeRate = u32s[5];
        c.strictStableDeviation = u32s[7];
        c.mlpPriceLowerBound = u96s[0];
        c.mlpPriceUpperBound = u96s[1];
    }

    function _convertPoolState(uint32[8] memory u32s, uint96[2] memory u96s)
        internal
        pure
        returns (LiquidityPoolState memory s)
    {
        s.lastFundingTime = u32s[2];
        s.sequence = u32s[6];
    }

    function _convertPoolStorage(uint32[8] memory u32s, uint96[2] memory u96s)
        internal
        pure
        returns (PoolStorage memory p)
    {
        p.shortFundingBaseRate8H = u32s[0];
        p.shortFundingLimitRate8H = u32s[1];
        p.lastFundingTime = u32s[2];
        p.fundingInterval = u32s[3];
        p.liquidityBaseFeeRate = u32s[4];
        p.liquidityDynamicFeeRate = u32s[5];
        p.sequence = u32s[6];
        p.strictStableDeviation = u32s[7];
        p.mlpPriceLowerBound = u96s[0];
        p.mlpPriceUpperBound = u96s[1];
    }

    function _convertAssetConfig(Asset memory asset) internal pure returns (AssetConfig memory c) {
        c.symbol = asset.symbol;
        c.tokenAddress = asset.tokenAddress;
        c.muxTokenAddress = asset.muxTokenAddress;
        c.id = asset.id;
        c.decimals = asset.decimals;
        c.isStable = asset.isStable;
        c.isTradable = asset.isTradable;
        c.isOpenable = asset.isOpenable;
        c.isShortable = asset.isShortable;
        c.useStableTokenForProfit = asset.useStableTokenForProfit;
        c.isEnabled = asset.isEnabled;
        c.isStrictStable = asset.isStrictStable;
        c.initialMarginRate = asset.initialMarginRate;
        c.maintenanceMarginRate = asset.maintenanceMarginRate;
        c.positionFeeRate = asset.positionFeeRate;
        c.minProfitRate = asset.minProfitRate;
        c.minProfitTime = asset.minProfitTime;
        c.maxLongPositionSize = asset.maxLongPositionSize;
        c.maxShortPositionSize = asset.maxShortPositionSize;
        c.spotWeight = asset.spotWeight;
        c.longFundingBaseRate8H = asset.longFundingBaseRate8H;
        c.longFundingLimitRate8H = asset.longFundingLimitRate8H;
        c.referenceOracleType = asset.referenceOracleType;
        c.referenceOracle = asset.referenceOracle;
        c.referenceDeviation = asset.referenceDeviation;
        c.halfSpread = asset.halfSpread;
    }

    function _convertAssetState(Asset memory asset) internal pure returns (AssetState memory s) {
        s.id = asset.id;
        s.longCumulativeFundingRate = asset.longCumulativeFundingRate;
        s.shortCumulativeFunding = asset.shortCumulativeFunding;
        s.spotLiquidity = asset.spotLiquidity;
        s.totalLongPosition = asset.totalLongPosition;
        s.totalShortPosition = asset.totalShortPosition;
        s.averageLongPrice = asset.averageLongPrice;
        s.averageShortPrice = asset.averageShortPrice;
        s.collectedFee = asset.collectedFee;
    }

    function _convertAssetStorage(Asset memory asset) internal pure returns (AssetStorage memory a) {
        a.symbol = asset.symbol;
        a.tokenAddress = asset.tokenAddress;
        a.muxTokenAddress = asset.muxTokenAddress;
        a.id = asset.id;
        a.decimals = asset.decimals;
        a.isStable = asset.isStable;
        a.isTradable = asset.isTradable;
        a.isOpenable = asset.isOpenable;
        a.isShortable = asset.isShortable;
        a.useStableTokenForProfit = asset.useStableTokenForProfit;
        a.isEnabled = asset.isEnabled;
        a.isStrictStable = asset.isStrictStable;
        a.initialMarginRate = asset.initialMarginRate;
        a.maintenanceMarginRate = asset.maintenanceMarginRate;
        a.positionFeeRate = asset.positionFeeRate;
        a.minProfitRate = asset.minProfitRate;
        a.minProfitTime = asset.minProfitTime;
        a.maxLongPositionSize = asset.maxLongPositionSize;
        a.maxShortPositionSize = asset.maxShortPositionSize;
        a.spotWeight = asset.spotWeight;
        a.longFundingBaseRate8H = asset.longFundingBaseRate8H;
        a.longFundingLimitRate8H = asset.longFundingLimitRate8H;
        a.referenceOracleType = asset.referenceOracleType;
        a.referenceOracle = asset.referenceOracle;
        a.referenceDeviation = asset.referenceDeviation;
        a.halfSpread = asset.halfSpread;

        a.longCumulativeFundingRate = asset.longCumulativeFundingRate;
        a.shortCumulativeFunding = asset.shortCumulativeFunding;
        a.spotLiquidity = asset.spotLiquidity;
        a.totalLongPosition = asset.totalLongPosition;
        a.totalShortPosition = asset.totalShortPosition;
        a.averageLongPrice = asset.averageLongPrice;
        a.averageShortPrice = asset.averageShortPrice;
        a.collectedFee = asset.collectedFee;
    }

    function _convertDexConfig(DexSpotConfiguration memory dexSpotConfiguration)
        internal
        pure
        returns (DexConfig memory d)
    {
        d.dexId = dexSpotConfiguration.dexId;
        d.dexType = dexSpotConfiguration.dexType;
        d.assetIds = dexSpotConfiguration.assetIds;
        d.assetWeightInDEX = dexSpotConfiguration.assetWeightInDex;
        d.dexWeight = dexSpotConfiguration.dexWeight;
        d.totalSpotInDEX = dexSpotConfiguration.totalSpotInDex;
    }

    function _convertDexStorage(DexSpotConfiguration memory dexSpotConfiguration)
        internal
        pure
        returns (DexStorage memory d)
    {
        d.dexId = dexSpotConfiguration.dexId;
        d.dexType = dexSpotConfiguration.dexType;
        d.assetIds = dexSpotConfiguration.assetIds;
        d.assetWeightInDEX = dexSpotConfiguration.assetWeightInDex;
        d.dexWeight = dexSpotConfiguration.dexWeight;
        d.totalSpotInDEX = dexSpotConfiguration.totalSpotInDex;
    }
}
