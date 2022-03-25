// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./Storage.sol";
import "../libraries/LibAsset.sol";
import "../libraries/LibMath.sol";
import "../core/Types.sol";

import "hardhat/console.sol";

contract Admin is Storage {
    using LibAsset for Asset;
    using LibMath for uint256;

    function addAsset(
        uint8 assetId,
        bytes32 symbol,
        uint8 decimals,
        bool isStable,
        address tokenAddress,
        address muxTokenAddress
    ) external onlyOwner {
        require(decimals <= 18, "Dcm"); // invalid DeCiMals
        require(assetId == _storage.assets.length, "AId"); // invalid AssetID
        require(assetId < 0xFF, "Fll"); // assets list is FuLL
        require(symbol != "", "Sym"); // invalid SYMbol

        _storage.assets.push();
        Asset storage asset = _storage.assets[assetId];
        asset.symbol = symbol;
        asset.id = assetId;
        asset.decimals = decimals;
        asset.isStable = isStable;
        asset.tokenAddress = tokenAddress;
        asset.muxTokenAddress = muxTokenAddress;
        emit AddAsset(assetId, symbol, decimals, isStable, tokenAddress, muxTokenAddress);
    }

    function setAssetParams(
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
    ) external onlyOwner {
        require(_hasAsset(assetId), "Lst"); // the asset is not LiSTed

        Asset storage asset = _storage.assets[assetId];
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

    function setAssetFlags(
        uint8 assetId,
        bool isTradable,
        bool isOpenable,
        bool isShortable,
        bool useStableTokenForProfit
    ) external onlyOwner {
        require(_hasAsset(assetId), "Lst"); // the asset is not LiSTed
        Asset storage asset = _storage.assets[assetId];
        asset.isTradable = isTradable;
        asset.isOpenable = isOpenable;
        asset.isShortable = isShortable;
        asset.useStableTokenForProfit = useStableTokenForProfit;
        emit SetAssetFlags(isTradable, isOpenable, isShortable, useStableTokenForProfit);
    }

    function setFundingParams(
        uint8 assetId,
        uint32 newBaseRate8H,
        uint32 newLimitRate8H
    ) external onlyOwner {
        require(_hasAsset(assetId), "Lst"); // the asset is not LiSTed

        if (_storage.assets[assetId].isStable) {
            _storage.shortFundingBaseRate8H = newBaseRate8H;
            _storage.shortFundingLimitRate8H = newLimitRate8H;
        } else {
            Asset storage asset = _storage.assets[assetId];
            asset.longFundingBaseRate8H = newBaseRate8H;
            asset.longFundingLimitRate8H = newLimitRate8H;
        }
        emit SetFundingParams(assetId, newBaseRate8H, newLimitRate8H);
    }

    function setNumbers(uint32 newFundingInterval, uint32 newLiquidityLockPeriod) external onlyOwner {
        require(newLiquidityLockPeriod <= 86400 * 30, "Prd");
        require(
            _storage.fundingInterval != newFundingInterval || _storage.liquidityLockPeriod != newLiquidityLockPeriod,
            "Chg"
        );
        if (_storage.fundingInterval != newFundingInterval) {
            emit SetFundingInterval(_storage.fundingInterval, newFundingInterval);
            _storage.fundingInterval = newFundingInterval;
        }
        if (_storage.liquidityLockPeriod != newLiquidityLockPeriod) {
            emit SetLiquidityLockPeriod(_storage.liquidityLockPeriod, newLiquidityLockPeriod);
            _storage.liquidityLockPeriod = newLiquidityLockPeriod;
        }
    }

    function withdrawLiquidity(uint8[] memory assetIds, uint256[] memory amounts) external onlyLiquidityManager {
        require(assetIds.length == amounts.length, "Len"); // LENgth of 2 arguments does not match
        uint256 length = assetIds.length;
        for (uint256 i = 0; i < length; i++) {
            Asset storage asset = _storage.assets[assetIds[i]];
            IERC20Upgradeable(asset.tokenAddress).transfer(msg.sender, amounts[i]);
            asset.spotLiquidity -= amounts[i].safeUint96();
            uint256 newBalance = IERC20Upgradeable(asset.tokenAddress).balanceOf(address(this));
            asset.tokenBalance = newBalance.safeUint128();
            emit TransferLiquidity(address(this), msg.sender, assetIds[i], amounts[i]);
        }
    }

    function depositLiquidity(uint8[] memory assetIds) external onlyLiquidityManager {
        require(assetIds.length > 0, "Mty"); // argument array is eMpTY
        uint256 length = assetIds.length;
        for (uint256 i = 0; i < length; i++) {
            Asset storage asset = _storage.assets[assetIds[i]];
            uint96 amount = asset.calcTransferredBalance().safeUint96();
            asset.spotLiquidity += amount;
            emit TransferLiquidity(msg.sender, address(this), assetIds[i], amount);
        }
    }
}
