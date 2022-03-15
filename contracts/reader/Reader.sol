// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../core/LiquidityPool.sol";
import "../liquidity/LiquidityManager.sol";

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
        uint256 lpDeduct;
        uint256 stableDeduct;
    }

    struct LiquidityPoolConfig {
        FundingConfiguration shortFunding;

        // call Getter.getLiquidityLockInfo to get
        // * fundingInterval
        // * liquidityLockPeriod,
    }

    struct LiquidityPoolState {
        FundingState shortFunding;

        // call Getter.getLiquidityLockInfo to get
        // * liquidityLock
    }

    struct AssetConfig {
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
        uint32 minProfitTime;
        uint96 maxLongPositionSize;
        uint96 maxShortPositionSize;
        FundingConfiguration longFunding;
        uint32 spotWeight;
    }

    struct AssetState {
        uint8 id;
        FundingState longFunding;
        uint96 liquidityBalance;
        uint96 totalLongPosition;
        uint96 averageLongPrice;
        uint96 totalShortPosition;
        uint96 averageShortPrice;
        uint128 collectedFee;
        uint256 deduct;
    }

    struct DexConfig {
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
    LiquidityManager public dex;
    address[] public deductWhiteList;

    constructor(
        address pool_,
        address mlp_,
        address dex_,
        address[] memory deductWhiteList_ // muxToken in these addresses are also not considered as debt
    ) {
        pool = LiquidityPool(pool_);
        mlp = IERC20(mlp_);
        dex = LiquidityManager(dex_);
        uint256 listLength = deductWhiteList_.length;
        for (uint256 i = 0; i < listLength; i++) {
            deductWhiteList.push(deductWhiteList_[i]);
        }
    }

    function getChainConfig() public view returns (ChainConfig memory chainConfig) {
        // from pool
        (uint32 baseRate8H, uint32 limitRate8H, , ) = pool.getShortFundingInfo();
        chainConfig.poolConfig.shortFunding.baseRate8H = baseRate8H;
        chainConfig.poolConfig.shortFunding.limitRate8H = limitRate8H;
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
        (, , uint128 cumulativeFunding, uint32 lastFundingTime) = pool.getShortFundingInfo();
        chainState.poolState.shortFunding.cumulativeFunding = cumulativeFunding;
        chainState.poolState.shortFunding.lastFundingTime = lastFundingTime;
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
        assetsState = new AssetState[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; i++) {
            Asset memory asset = pool.getAssetInfo(assetIds[i]);
            assetsState[i] = _convertAssetState(asset);
        }
    }

    function getLiquidityLockInfo(address lp) public view returns (uint32 liquidityLockPeriod, uint32 liquidityLock) {
        return pool.getLiquidityLockInfo(lp);
    }

    function _convertAssetConfig(Asset memory asset) internal pure returns (AssetConfig memory c) {
        c.symbol = asset.symbol;
        c.id = asset.id;
        c.decimals = asset.decimals;
        c.isStable = asset.isStable;
        c.tokenAddress = asset.tokenAddress;
        c.muxTokenAddress = asset.muxTokenAddress;
        c.initialMarginRate = asset.initialMarginRate;
        c.maintenanceMarginRate = asset.maintenanceMarginRate;
        c.positionFeeRate = asset.positionFeeRate;
        c.minProfitRate = asset.minProfitRate;
        c.minProfitTime = asset.minProfitTime;
        c.maxLongPositionSize = asset.maxLongPositionSize;
        c.maxShortPositionSize = asset.maxShortPositionSize;
        c.isTradable = asset.isTradable;
        c.isOpenable = asset.isOpenable;
        c.isShortable = asset.isShortable;
        c.useStableTokenForProfit = asset.useStableTokenForProfit;
        c.longFunding = asset.longFundingConfiguration;
        c.spotWeight = asset.spotWeight;
    }

    function _convertAssetState(Asset memory asset) internal pure returns (AssetState memory s) {
        s.id = asset.id;
        s.longFunding = asset.longFunding;
        s.totalLongPosition = asset.totalLongPosition;
        s.totalShortPosition = asset.totalShortPosition;
        s.liquidityBalance = asset.liquidityBalance;
        s.averageLongPrice = asset.averageLongPrice;
        s.averageShortPrice = asset.averageShortPrice;
        s.collectedFee = asset.collectedFee;
    }

    function _convertDexConfig(DexSpotConfiguration memory dexSpotConfiguration)
        internal
        pure
        returns (DexConfig memory d)
    {
        d.dexId = dexSpotConfiguration.dexId;
        d.assetIds = dexSpotConfiguration.assetIds;
        d.assetWeightInDEX = dexSpotConfiguration.assetWeightInDex;
        d.dexWeight = dexSpotConfiguration.dexWeight;
    }
}
