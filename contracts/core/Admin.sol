// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./Storage.sol";
import "../libraries/LibAsset.sol";
import "../libraries/LibMath.sol";
import "../libraries/LibReferenceOracle.sol";
import "../core/Types.sol";

contract Admin is Storage {
    using LibAsset for Asset;
    using LibMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function addAsset(
        uint8 assetId,
        bytes32 symbol,
        uint8 decimals,
        bool isStable,
        address tokenAddress,
        address muxTokenAddress
    ) external onlyOwner {
        require(decimals <= 18, "DCM"); // invalid DeCiMals
        require(assetId == _storage.assets.length, "AID"); // invalid AssetID
        require(assetId < 0xFF, "FLL"); // assets list is FuLL
        require(symbol != "", "SYM"); // invalid SYMbol

        _storage.assets.push();
        Asset storage asset = _storage.assets[assetId];
        asset.symbol = symbol;
        asset.id = assetId;
        asset.decimals = decimals;
        asset.isStable = isStable;
        asset.tokenAddress = tokenAddress;
        asset.muxTokenAddress = muxTokenAddress;
        emit AddAsset(assetId, symbol, decimals, isStable, tokenAddress, muxTokenAddress);
        _updateSequence();
    }

    function setAssetSymbol(uint8 assetId, bytes32 symbol) external onlyOwner {
        require(_hasAsset(assetId), "LST"); // the asset is not LiSTed
        require(symbol != "", "SYM"); // invalid SYMbol

        Asset storage asset = _storage.assets[assetId];
        require(asset.symbol != symbol, "CHG"); // setting is not CHanGed
        asset.symbol = symbol;
        emit SetAssetSymbol(assetId, symbol);
        _updateSequence();
    }

    function setAssetParams(
        uint8 assetId,
        uint32 newInitialMarginRate, // 1e5
        uint32 newMaintenanceMarginRate, // 1e5
        uint32 newPositionFeeRate, // 1e5
        uint32 newMinProfitRate, // 1e5
        uint32 newMinProfitTime, // 1e0
        uint96 newMaxLongPositionSize,
        uint96 newMaxShortPositionSize,
        uint32 newSpotWeight,
        uint32 newHalfSpread
    ) external onlyOwner {
        require(_hasAsset(assetId), "LST"); // the asset is not LiSTed
        Asset storage asset = _storage.assets[assetId];
        require(asset.initialMarginRate == 0 || newInitialMarginRate <= asset.initialMarginRate, "IMR"); // Initial Margin Raised
        require(asset.maintenanceMarginRate == 0 || newMaintenanceMarginRate <= asset.maintenanceMarginRate, "MMR"); // Maintenance Margin Raised
        asset.initialMarginRate = newInitialMarginRate;
        asset.maintenanceMarginRate = newMaintenanceMarginRate;
        asset.positionFeeRate = newPositionFeeRate;
        asset.minProfitRate = newMinProfitRate;
        asset.minProfitTime = newMinProfitTime;
        asset.maxLongPositionSize = newMaxLongPositionSize;
        asset.maxShortPositionSize = newMaxShortPositionSize;
        asset.spotWeight = newSpotWeight;
        asset.halfSpread = newHalfSpread;
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
            newHalfSpread
        );
        _updateSequence();
    }

    function setAssetFlags(
        uint8 assetId,
        bool isTradable,
        bool isOpenable,
        bool isShortable,
        bool useStableTokenForProfit,
        bool isEnabled,
        bool isStrictStable
    ) external onlyOwner {
        require(_hasAsset(assetId), "LST"); // the asset is not LiSTed
        Asset storage asset = _storage.assets[assetId];
        if (!asset.isStable) {
            require(!isStrictStable, "STB"); // the asset is impossible to be a strict STaBle coin
        }
        asset.isTradable = isTradable;
        asset.isOpenable = isOpenable;
        asset.isShortable = isShortable;
        asset.useStableTokenForProfit = useStableTokenForProfit;
        asset.isEnabled = isEnabled;
        asset.isStrictStable = isStrictStable;
        emit SetAssetFlags(
            assetId,
            isTradable,
            isOpenable,
            isShortable,
            useStableTokenForProfit,
            isEnabled,
            isStrictStable
        );
        _updateSequence();
    }

    function pauseAll() external onlyOwner {
        for (uint8 assetId = 0; assetId < _storage.assets.length; assetId++) {
            Asset storage asset = _storage.assets[assetId];
            asset.isEnabled = false;
            emit SetAssetFlags(
                assetId,
                asset.isTradable,
                asset.isOpenable,
                asset.isShortable,
                asset.useStableTokenForProfit,
                asset.isEnabled,
                asset.isStrictStable
            );
        }
        _updateSequence();
    }

    function setFundingParams(
        uint8 assetId,
        uint32 newBaseRate8H,
        uint32 newLimitRate8H
    ) external onlyOwner {
        require(_hasAsset(assetId), "LST"); // the asset is not LiSTed
        if (_storage.assets[assetId].isStable) {
            _storage.shortFundingBaseRate8H = newBaseRate8H;
            _storage.shortFundingLimitRate8H = newLimitRate8H;
        } else {
            Asset storage asset = _storage.assets[assetId];
            asset.longFundingBaseRate8H = newBaseRate8H;
            asset.longFundingLimitRate8H = newLimitRate8H;
        }
        emit SetFundingParams(assetId, newBaseRate8H, newLimitRate8H);
        _updateSequence();
    }

    function setReferenceOracle(
        uint8 assetId,
        ReferenceOracleType referenceOracleType,
        address referenceOracle,
        uint32 referenceDeviation // 1e5
    ) external onlyOwner {
        LibReferenceOracle.checkParameters(referenceOracleType, referenceOracle, referenceDeviation);
        require(_hasAsset(assetId), "LST"); // the asset is not LiSTed
        Asset storage asset = _storage.assets[assetId];
        asset.referenceOracleType = uint8(referenceOracleType);
        asset.referenceOracle = referenceOracle;
        asset.referenceDeviation = referenceDeviation;
        emit SetReferenceOracle(assetId, uint8(referenceOracleType), referenceOracle, referenceDeviation);
        _updateSequence();
    }

    function setNumbers(
        uint32 newFundingInterval,
        uint96 newMlpPriceLowerBound,
        uint96 newMlpPriceUpperBound,
        uint32 newLiquidityBaseFeeRate, // 1e5
        uint32 newLiquidityDynamicFeeRate, // 1e5
        uint32 newStrictStableDeviation // 1e5
    ) external onlyOwner {
        require(newLiquidityBaseFeeRate < 1e5, "F>1"); // %fee > 100%
        require(newLiquidityDynamicFeeRate < 1e5, "F>1"); // %fee > 100%
        require(newStrictStableDeviation < 1e5, "D>1"); // %deviation > 100%
        if (_storage.fundingInterval != newFundingInterval) {
            emit SetFundingInterval(_storage.fundingInterval, newFundingInterval);
            _storage.fundingInterval = newFundingInterval;
        }
        if (
            _storage.mlpPriceLowerBound != newMlpPriceLowerBound || _storage.mlpPriceUpperBound != newMlpPriceUpperBound
        ) {
            _storage.mlpPriceLowerBound = newMlpPriceLowerBound;
            _storage.mlpPriceUpperBound = newMlpPriceUpperBound;
            emit SetMlpPriceRange(newMlpPriceLowerBound, newMlpPriceUpperBound);
        }
        if (
            _storage.liquidityBaseFeeRate != newLiquidityBaseFeeRate ||
            _storage.liquidityDynamicFeeRate != newLiquidityDynamicFeeRate
        ) {
            _storage.liquidityBaseFeeRate = newLiquidityBaseFeeRate;
            _storage.liquidityDynamicFeeRate = newLiquidityDynamicFeeRate;
            emit SetLiquidityFee(newLiquidityBaseFeeRate, newLiquidityDynamicFeeRate);
        }
        if (_storage.strictStableDeviation != newStrictStableDeviation) {
            _storage.strictStableDeviation = newStrictStableDeviation;
            emit SetStrictStableDeviation(newStrictStableDeviation);
        }
        _updateSequence();
    }

    function withdrawCollectedFee(uint8[] memory assetIds) external onlyOwner {
        for (uint256 i = 0; i < assetIds.length; i++) {
            uint8 assetId = assetIds[i];
            Asset storage asset = _storage.assets[assetId];
            uint96 collectedFee = asset.collectedFee;
            require(collectedFee <= asset.spotLiquidity, "LIQ"); // insufficient LIQuidity
            asset.collectedFee = 0;
            asset.spotLiquidity -= collectedFee;
            uint256 rawAmount = asset.toRaw(collectedFee);
            IERC20Upgradeable(asset.tokenAddress).safeTransfer(msg.sender, rawAmount);
            emit WithdrawCollectedFee(assetId, collectedFee);
        }
        _updateSequence();
    }

    function transferLiquidityOut(uint8[] memory assetIds, uint256[] memory rawAmounts) external onlyLiquidityManager {
        uint256 length = assetIds.length;
        require(length > 0, "MTY"); // argument array is eMpTY
        require(assetIds.length == rawAmounts.length, "LEN"); // LENgth of 2 arguments does not match
        for (uint256 i = 0; i < length; i++) {
            Asset storage asset = _storage.assets[assetIds[i]];
            IERC20Upgradeable(asset.tokenAddress).transfer(msg.sender, rawAmounts[i]);
            uint96 wadAmount = asset.toWad(rawAmounts[i]);
            require(asset.spotLiquidity >= wadAmount, "NLT"); // not enough liquidity
            asset.spotLiquidity -= wadAmount;
            emit TransferLiquidity(address(this), msg.sender, assetIds[i], rawAmounts[i]);
        }
        _updateSequence();
    }

    function transferLiquidityIn(uint8[] memory assetIds, uint256[] memory rawAmounts) external onlyLiquidityManager {
        uint256 length = assetIds.length;
        require(length > 0, "MTY"); // argument array is eMpTY
        require(assetIds.length == rawAmounts.length, "LEN"); // LENgth of 2 arguments does not match
        for (uint256 i = 0; i < length; i++) {
            Asset storage asset = _storage.assets[assetIds[i]];
            asset.spotLiquidity += asset.toWad(rawAmounts[i]);
            emit TransferLiquidity(msg.sender, address(this), assetIds[i], rawAmounts[i]);
        }
        _updateSequence();
    }
}
