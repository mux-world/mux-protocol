// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "../libraries/LibAsset.sol";
import "../libraries/LibMath.sol";

import "../core/Types.sol";

library LibMuxAdmin {
    using LibAsset for Asset;
    using LibMath for uint256;

    event SetFundingParams(uint8 tokenId, uint32 newBaseRate8H, uint32 newLimitRate8H);
    event SetFundingInterval(uint32 oldFundingInterval, uint32 newFundingInterval);
    event AddAsset(
        uint8 indexed id,
        bytes32 symbol,
        uint8 decimals,
        bool isStable,
        address tokenAddress,
        address muxTokenAddress
    );
    event SetAssetParams(
        uint8 indexed assetId,
        uint32 newInitialMarginRate,
        uint32 newMaintenanceMarginRate,
        uint32 newPositionFeeRate,
        uint32 newMinProfitRate,
        uint32 newMinProfitTime,
        uint96 newMaxLongPositionSize,
        uint96 newMaxShortPositionSize,
        uint32 newSpotWeight,
        address newBackupOracle,
        uint8 newBackupOracleType
    );
    event SetAssetFlags(bool isTradable, bool isOpenable, bool isShortable, bool useStableTokenForProfit);
    event SetAddresses(
        address oldOrderBook,
        address newOrderBook,
        address oldLiquidityManager,
        address newLiquidityManager
    );
    event SetLiquidityLockPeriod(uint32 oldLockPeriod, uint32 newLockPeriod);
    event TransferLiquidity(address indexed sender, address indexed recipient, uint8 assetId, uint256 amount);

    function setParams(
        LiquidityPoolStorage storage pool,
        AdminParamsType paramType,
        bytes calldata params
    ) external {
        if (paramType == AdminParamsType.AddAsset) {
            (
                uint8 assetId,
                bytes32 symbol,
                uint8 decimals,
                bool isStable,
                address tokenAddress,
                address muxTokenAddress
            ) = abi.decode(params, (uint8, bytes32, uint8, bool, address, address));
            _addAsset(pool, assetId, symbol, decimals, isStable, tokenAddress, muxTokenAddress);
        } else if (paramType == AdminParamsType.SetAssetParams) {
            (
                uint8 assetId,
                uint32 newInitialMarginRate,
                uint32 newMaintenanceMarginRate,
                uint32 newPositionFeeRate,
                uint32 newMinProfitRate,
                uint32 newMinProfitTime,
                uint96 newMaxLongPositionSize,
                uint96 newMaxShortPositionSize,
                uint32 newSpotWeight,
                address newBackupOracle,
                uint8 newBackupOracleType
            ) = abi.decode(
                    params,
                    (uint8, uint32, uint32, uint32, uint32, uint32, uint96, uint96, uint32, address, uint8)
                );
            _setAssetParams(
                pool,
                assetId,
                newInitialMarginRate,
                newMaintenanceMarginRate,
                newPositionFeeRate,
                newMinProfitRate,
                newMinProfitTime,
                newMaxLongPositionSize,
                newMaxShortPositionSize,
                newSpotWeight,
                newBackupOracle,
                newBackupOracleType
            );
        } else if (paramType == AdminParamsType.SetAssetFlags) {
            (uint8 assetId, bool isTradable, bool isOpenable, bool isShortable, bool useStableTokenForProfit) = abi
                .decode(params, (uint8, bool, bool, bool, bool));
            _setAssetFlags(pool, assetId, isTradable, isOpenable, isShortable, useStableTokenForProfit);
        } else if (paramType == AdminParamsType.SetFundingParams) {
            (uint8 assetId, uint32 newBaseRate8H, uint32 newLimitRate8H) = abi.decode(params, (uint8, uint32, uint32));
            _setFundingParams(pool, assetId, newBaseRate8H, newLimitRate8H);
        } else if (paramType == AdminParamsType.SetFundingInterval) {
            uint32 newFundingInterval = abi.decode(params, (uint32));
            _setFundingInterval(pool, newFundingInterval);
        } else if (paramType == AdminParamsType.SetAddresses) {
            (address orderBook, address liquidityManager) = abi.decode(params, (address, address));
            _setAddresses(pool, orderBook, liquidityManager);
        } else if (paramType == AdminParamsType.SetLiquidityLockPeriod) {
            uint32 newLockPeriod = abi.decode(params, (uint32));
            _setLiquidityLockPeriod(pool, newLockPeriod);
        } else if (paramType == AdminParamsType.WithdrawLiquidity) {
            (uint8[] memory assetIds, uint256[] memory amounts) = abi.decode(params, (uint8[], uint256[]));
            _withdrawLiquidity(pool, assetIds, amounts);
        } else if (paramType == AdminParamsType.DepositLiquidity) {
            uint8[] memory assetIds = abi.decode(params, (uint8[]));
            _depositLiquidity(pool, assetIds);
        } else {
            revert("UnknownKey");
        }
    }

    function _hasAsset(LiquidityPoolStorage storage pool, uint8 assetId) internal view returns (bool) {
        return assetId < pool.assets.length;
    }

    function _addAsset(
        LiquidityPoolStorage storage pool,
        uint8 assetId,
        bytes32 symbol,
        uint8 decimals,
        bool isStable,
        address tokenAddress,
        address muxTokenAddress
    ) internal {
        require(decimals <= 18, "DecimalsOutOfRange");
        require(assetId == pool.assets.length, "IdNotMatch");
        require(symbol != "", "EmptySymbol");

        pool.assets.push();
        Asset storage asset = pool.assets[assetId];
        asset.symbol = symbol;
        asset.id = assetId;
        asset.decimals = decimals;
        asset.isStable = isStable;
        asset.tokenAddress = tokenAddress;
        asset.muxTokenAddress = muxTokenAddress;
        emit AddAsset(assetId, symbol, decimals, isStable, tokenAddress, muxTokenAddress);
    }

    function _setAssetParams(
        LiquidityPoolStorage storage pool,
        uint8 assetId,
        uint32 newInitialMarginRate,
        uint32 newMaintenanceMarginRate,
        uint32 newPositionFeeRate,
        uint32 newMinProfitRate,
        uint32 newMinProfitTime,
        uint96 newMaxLongPositionSize,
        uint96 newMaxShortPositionSize,
        uint32 newSpotWeight,
        address newBackupOracle,
        uint8 newBackupOracleType
    ) internal {
        require(_hasAsset(pool, assetId), "AssetNotExists");

        Asset storage asset = pool.assets[assetId];
        asset.initialMarginRate = newInitialMarginRate;
        asset.maintenanceMarginRate = newMaintenanceMarginRate; // 1e5
        asset.positionFeeRate = newPositionFeeRate; // 1e5
        asset.minProfitRate = newMinProfitRate; // 1e5
        asset.minProfitTime = newMinProfitTime;
        asset.maxLongPositionSize = newMaxLongPositionSize;
        asset.maxShortPositionSize = newMaxShortPositionSize;
        asset.spotWeight = newSpotWeight;
        asset.backupOracle = newBackupOracle;
        asset.backupOracleType = newBackupOracleType;

        emit SetAssetParams(
            assetId,
            newInitialMarginRate,
            newMaintenanceMarginRate,
            newPositionFeeRate,
            newMinProfitRate,
            newMinProfitTime,
            newMaxLongPositionSize,
            newMaxShortPositionSize,
            newSpotWeight,
            newBackupOracle,
            newBackupOracleType
        );
    }

    function _setAssetFlags(
        LiquidityPoolStorage storage pool,
        uint8 assetId,
        bool isTradable,
        bool isOpenable,
        bool isShortable,
        bool useStableTokenForProfit
    ) internal {
        require(_hasAsset(pool, assetId), "AssetNotExists");
        Asset storage asset = pool.assets[assetId];
        asset.isTradable = isTradable;
        asset.isOpenable = isOpenable;
        asset.isShortable = isShortable;
        asset.useStableTokenForProfit = useStableTokenForProfit;
        emit SetAssetFlags(isTradable, isOpenable, isShortable, useStableTokenForProfit);
    }

    function _setFundingParams(
        LiquidityPoolStorage storage pool,
        uint8 assetId,
        uint32 newBaseRate8H,
        uint32 newLimitRate8H
    ) internal {
        require(_hasAsset(pool, assetId), "AssetNotExists");

        FundingConfiguration storage configuration;
        if (pool.assets[assetId].isStable) {
            configuration = pool.shortFundingConfiguration;
        } else {
            configuration = pool.assets[assetId].longFundingConfiguration;
        }
        configuration.baseRate8H = newBaseRate8H;
        configuration.limitRate8H = newLimitRate8H;
        emit SetFundingParams(assetId, newBaseRate8H, newLimitRate8H);
    }

    function _setFundingInterval(LiquidityPoolStorage storage pool, uint32 newFundingInterval) internal {
        require(pool.fundingInterval != newFundingInterval, "NoChanges");
        emit SetFundingInterval(pool.fundingInterval, newFundingInterval);
        pool.fundingInterval = newFundingInterval;
    }

    function _setAddresses(
        LiquidityPoolStorage storage pool,
        address newOrderBook,
        address newLiquidityManager
    ) internal {
        require(pool.orderBook != newOrderBook || pool.liquidityManager != newLiquidityManager, "NoChanges");
        emit SetAddresses(pool.orderBook, newOrderBook, pool.liquidityManager, newLiquidityManager);
        pool.orderBook = newOrderBook;
        pool.liquidityManager = newLiquidityManager;
    }

    function _setLiquidityLockPeriod(LiquidityPoolStorage storage pool, uint32 newLockPeriod) internal {
        require(newLockPeriod <= 86400 * 30, "PeriodTooLong");
        emit SetLiquidityLockPeriod(pool.liquidityLockPeriod, newLockPeriod);
        pool.liquidityLockPeriod = newLockPeriod;
    }

    function _withdrawLiquidity(
        LiquidityPoolStorage storage pool,
        uint8[] memory assetIds,
        uint256[] memory amounts
    ) internal {
        require(assetIds.length == amounts.length, "ParamsLengthMismatch");
        uint256 length = assetIds.length;
        for (uint256 i = 0; i < length; i++) {
            Asset storage asset = pool.assets[assetIds[i]];
            IERC20Upgradeable(asset.tokenAddress).transfer(msg.sender, amounts[i]);
            asset.liquidityBalance -= amounts[i].safeUint96();
            uint256 newBalance = IERC20Upgradeable(asset.tokenAddress).balanceOf(address(this));
            asset.tokenBalance = newBalance.safeUint128();
            emit TransferLiquidity(address(this), msg.sender, assetIds[i], amounts[i]);
        }
    }

    function _depositLiquidity(
        LiquidityPoolStorage storage pool,
        uint8[] memory assetIds // uint256[] memory amounts
    ) internal {
        require(assetIds.length > 0, "NoAssets");
        uint256 length = assetIds.length;
        for (uint256 i = 0; i < length; i++) {
            Asset storage asset = pool.assets[assetIds[i]];
            uint96 amount = asset.calcTransferredBalance().safeUint96();
            asset.liquidityBalance += amount;
            emit TransferLiquidity(msg.sender, address(this), assetIds[i], amount);
        }
    }
}
