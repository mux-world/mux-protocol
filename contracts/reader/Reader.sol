// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IOrderBook.sol";
import "../interfaces/ILiquidityManager.sol";
import "../libraries/LibAsset.sol";

contract Reader {
    struct ChainStorage {
        PoolStorage pool;
        AssetStorage[] assets;
        DexStorage[] dexes;
        uint32 liquidityLockPeriod; // 1e0
        uint32 marketOrderTimeout; // 1e0
        uint32 maxLimitOrderTimeout; // 1e0
        uint256 lpDeduct; // MLP totalSupply = PRE_MINED - Σ_chains lpDeduct
        uint256 stableDeduct; // debt of stable coins = PRE_MINED - Σ_chains stableDeduct
        bool isPositionOrderPaused;
        bool isLiquidityOrderPaused;
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

    struct AssetStorage {
        // assets with the same symbol in different chains are the same asset. they shares the same muxToken. so debts of the same symbol
        // can be accumulated across chains (see Reader.AssetState.deduct). ex: ERC20(fBNB).symbol should be "BNB", so that BNBs of
        // different chains are the same.
        // since muxToken of all stable coins is the same and is calculated separately (see Reader.ChainState.stableDeduct), stable coin
        // symbol can be different (ex: "USDT", "USDT.e" and "fUSDT").
        bytes32 symbol;
        address tokenAddress; // erc20.address
        address muxTokenAddress; // muxToken.address. all stable coins share the same muxTokenAddress
        uint8 id;
        uint8 decimals; // erc20.decimals
        uint56 flags; // a bitset of ASSET_*
        uint32 initialMarginRate; // 1e5
        uint32 maintenanceMarginRate; // 1e5
        uint32 positionFeeRate; // 1e5
        uint32 liquidationFeeRate; // 1e5
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
        uint128 longCumulativeFundingRate; // Σ_t fundingRate_t
        uint128 shortCumulativeFunding; // Σ_t fundingRate_t * indexPrice_t
        uint96 spotLiquidity;
        uint96 credit;
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
            if ((assets[i].flags & ASSET_IS_STABLE) != 0) {
                stableMuxTokenAddress = assets[i].muxTokenAddress;
            } else {
                chain.assets[i].deduct = getDeduct(assets[i].muxTokenAddress);
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
        chain.marketOrderTimeout = orderBook.marketOrderTimeout();
        chain.maxLimitOrderTimeout = orderBook.maxLimitOrderTimeout();
        chain.isPositionOrderPaused = orderBook.isPositionOrderPaused();
        chain.isLiquidityOrderPaused = orderBook.isLiquidityOrderPaused();

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

    function getOrders(
        uint64[] memory orderIds
    ) public view returns (bytes32[3][] memory orders, bool[] memory isExist) {
        orders = new bytes32[3][](orderIds.length);
        isExist = new bool[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            (orders[i], isExist[i]) = orderBook.getOrder(orderIds[i]);
        }
    }

    function getSubAccountsAndOrders(
        bytes32[] memory subAccountIds,
        uint64[] memory orderIds
    )
        public
        view
        returns (SubAccountState[] memory subAccounts, bytes32[3][] memory orders, bool[] memory isOrderExist)
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

    function getErc20Balances(address[] memory tokens, address owner) public view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(owner);
        }
    }

    function getPositionOrdersExtra(uint64[] memory orderIds) public view returns (PositionOrderExtra[] memory extras) {
        extras = new PositionOrderExtra[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            extras[i] = orderBook.positionOrderExtras(orderIds[i]);
        }
    }

    function _convertPoolStorage(
        uint32[8] memory u32s,
        uint96[2] memory u96s
    ) internal pure returns (PoolStorage memory p) {
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

    function _convertAssetStorage(Asset memory asset) internal pure returns (AssetStorage memory a) {
        a.symbol = asset.symbol;
        a.tokenAddress = asset.tokenAddress;
        a.muxTokenAddress = asset.muxTokenAddress;
        a.id = asset.id;
        a.decimals = asset.decimals;
        a.flags = asset.flags;
        a.initialMarginRate = asset.initialMarginRate;
        a.maintenanceMarginRate = asset.maintenanceMarginRate;
        a.positionFeeRate = asset.positionFeeRate;
        a.liquidationFeeRate = asset.liquidationFeeRate;
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
        a.credit = asset.credit;
        a.totalLongPosition = asset.totalLongPosition;
        a.totalShortPosition = asset.totalShortPosition;
        a.averageLongPrice = asset.averageLongPrice;
        a.averageShortPrice = asset.averageShortPrice;
        a.collectedFee = asset.collectedFee;
    }

    function _convertDexStorage(
        DexSpotConfiguration memory dexSpotConfiguration
    ) internal pure returns (DexStorage memory d) {
        d.dexId = dexSpotConfiguration.dexId;
        d.dexType = dexSpotConfiguration.dexType;
        d.assetIds = dexSpotConfiguration.assetIds;
        d.assetWeightInDEX = dexSpotConfiguration.assetWeightInDex;
        d.dexWeight = dexSpotConfiguration.dexWeight;
        d.totalSpotInDEX = dexSpotConfiguration.totalSpotInDex;
    }
}
