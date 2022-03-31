// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../core/LiquidityPool.sol";
import "../interfaces/IMlpTimeLock.sol";
import "../interfaces/ILiquidityManager.sol";

contract Reader {
    using SafeMathUpgradeable for uint256;

    struct ChainConfig {
        LiquidityPoolConfig poolConfig;
        AssetConfig[] assetConfigs;
        DexConfig[] dexConfigs;
    }

    struct ChainState {
        LiquidityPoolState poolState;
        AssetState[] assetStates;
        DexState[] dexStates;
        uint256 lpDeduct; // MLP totalSupply = PRE_MINED - Σ_chains lpDeduct
        uint256 stableDeduct; // debt of stable coins = PRE_MINED - Σ_chains stableDeduct
    }

    struct LiquidityPoolConfig {
        uint32 shortFundingBaseRate8H; // 1e5
        uint32 shortFundingLimitRate8H; // 1e5
        uint32 fundingInterval; // 1e0
    }

    struct LiquidityPoolState {
        uint128 shortCumulativeFunding;
        uint32 lastFundingTime; // 1e0
    }

    struct AssetConfig {
        bytes32 symbol;
        // -----------------
        uint8 id;
        uint8 decimals;
        bool isStable;
        bool isTradable;
        bool isOpenable;
        bool isShortable;
        bool useStableTokenForProfit;
        uint8 referenceOracleType;
        uint96 maxLongPositionSize;
        uint96 maxShortPositionSize;
        // -----------------
        uint32 initialMarginRate; // 1e5
        uint32 maintenanceMarginRate; // 1e5
        uint32 positionFeeRate; // 1e5
        uint32 minProfitRate; // 1e5
        uint32 minProfitTime; // 1e0
        uint32 longFundingBaseRate8H; // 1e5
        uint32 longFundingLimitRate8H; // 1e5
        uint32 spotWeight;
        // -----------------
        address referenceOracle;
        address tokenAddress;
        address muxTokenAddress;
        uint32 referenceDeviation;
    }

    struct AssetState {
        uint8 id;
        uint96 spotLiquidity;
        uint128 collectedFee;
        // note: 24 bits remaining
        // -----------------
        uint128 longCumulativeFunding;
        uint128 shortCumulativeFunding; // all unstable asset.shortCumulativeFunding are the same as LiquidityPoolState.shortCumulativeFunding.
        // -----------------
        uint96 totalLongPosition;
        uint96 averageLongPrice;
        // -----------------
        uint96 totalShortPosition;
        uint96 averageShortPrice;
        // -----------------
        uint256 deduct; // debt of a non-stable coin = PRE_MINED - Σ_chains deduct
    }

    struct DexConfig {
        string name;
        uint8 dexId;
        uint8[] assetIds;
        uint32[] assetWeightInDEX;
        uint32 dexWeight;
    }

    struct DexState {
        uint8 dexId;
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

    LiquidityPool public pool;
    IERC20 public mlp;
    ILiquidityManager public dex;
    IMlpTimeLock public mlpTimeLock;
    address[] public deductWhiteList;

    constructor(
        address pool_,
        address mlp_,
        address dex_,
        address mlpTimeLock_,
        address[] memory deductWhiteList_ // muxToken in these addresses are also not considered as debt
    ) {
        pool = LiquidityPool(payable(pool_));
        mlp = IERC20(mlp_);
        dex = ILiquidityManager(dex_);
        mlpTimeLock = IMlpTimeLock(mlpTimeLock_);
        uint256 listLength = deductWhiteList_.length;
        for (uint256 i = 0; i < listLength; i++) {
            deductWhiteList.push(deductWhiteList_[i]);
        }
    }

    function getChainConfig() public view returns (ChainConfig memory chainConfig) {
        // from pool
        (, uint32[4] memory u32s) = pool.getLiquidityPoolStorage();
        chainConfig.poolConfig.shortFundingBaseRate8H = u32s[0];
        chainConfig.poolConfig.shortFundingLimitRate8H = u32s[1];
        chainConfig.poolConfig.fundingInterval = u32s[3];
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
    }

    function getChainState() public returns (ChainState memory chainState) {
        // from pool
        (uint128[1] memory u128s, uint32[4] memory u32s) = pool.getLiquidityPoolStorage();
        chainState.poolState.shortCumulativeFunding = u128s[0];
        chainState.poolState.lastFundingTime = u32s[2];
        // from assets
        address stableMuxTokenAddress;
        Asset[] memory assets = pool.getAllAssetInfo();
        uint256 assetLength = assets.length;
        chainState.assetStates = new AssetState[](assetLength);
        for (uint256 i = 0; i < assetLength; i++) {
            chainState.assetStates[i] = _convertAssetState(assets[i]);
            if (!assets[i].isStable) {
                chainState.assetStates[i].deduct = getDeduct(assets[i].muxTokenAddress);
                chainState.assetStates[i].shortCumulativeFunding = chainState.poolState.shortCumulativeFunding;
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
            chainState.dexStates[i].liquidityBalance = liquidities;
        }
        // Deduct
        chainState.lpDeduct = getDeduct(address(mlp));
        if (stableMuxTokenAddress != address(0)) {
            chainState.stableDeduct = getDeduct(stableMuxTokenAddress);
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

    function getAssetsState(uint8[] memory assetIds) public view returns (AssetState[] memory assetsState) {
        (uint128[1] memory u128s, ) = pool.getLiquidityPoolStorage();
        assetsState = new AssetState[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; i++) {
            Asset memory asset = pool.getAssetInfo(assetIds[i]);
            assetsState[i] = _convertAssetState(asset);
            if (!asset.isStable) {
                assetsState[i].shortCumulativeFunding = u128s[0];
            }
        }
    }

    function getLiquidityLockInfo(address lp)
        public
        view
        returns (
            uint32 liquidityLockPeriod,
            uint32 lastAddedTime,
            uint96 pendingMLP
        )
    {
        return mlpTimeLock.getLiquidityLockInfo(lp);
    }

    function _convertAssetConfig(Asset memory asset) internal pure returns (AssetConfig memory c) {
        c.symbol = asset.symbol;
        c.id = asset.id;
        c.decimals = asset.decimals;
        c.isStable = asset.isStable;
        c.isTradable = asset.isTradable;
        c.isOpenable = asset.isOpenable;
        c.isShortable = asset.isShortable;
        c.useStableTokenForProfit = asset.useStableTokenForProfit;
        c.referenceOracleType = asset.referenceOracleType;
        c.referenceOracle = asset.referenceOracle;
        c.referenceDeviation = asset.referenceDeviation;
        c.tokenAddress = asset.tokenAddress;
        c.muxTokenAddress = asset.muxTokenAddress;
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
    }

    function _convertAssetState(Asset memory asset) internal pure returns (AssetState memory s) {
        s.id = asset.id;
        s.longCumulativeFunding = asset.longCumulativeFunding;
        s.spotLiquidity = asset.spotLiquidity;
        s.totalLongPosition = asset.totalLongPosition;
        s.totalShortPosition = asset.totalShortPosition;
        s.averageLongPrice = asset.averageLongPrice;
        s.averageShortPrice = asset.averageShortPrice;
        s.collectedFee = asset.collectedFee;
    }

    function _convertDexConfig(DexSpotConfiguration memory dexSpotConfiguration)
        internal
        pure
        returns (DexConfig memory d)
    {
        d.name = dexSpotConfiguration.name;
        d.dexId = dexSpotConfiguration.dexId;
        d.assetIds = dexSpotConfiguration.assetIds;
        d.assetWeightInDEX = dexSpotConfiguration.assetWeightInDex;
        d.dexWeight = dexSpotConfiguration.dexWeight;
    }
}
