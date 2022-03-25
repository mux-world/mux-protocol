// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../libraries/LibAsset.sol";
import "../libraries/LibSubAccount.sol";
import "../libraries/LibMath.sol";

import "./Account.sol";
import "./Storage.sol";

contract Trade is Storage, Account {
    using LibAsset for Asset;
    using LibMath for uint256;
    using LibSubAccount for bytes32;

    function openPosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external onlyOrderBook {
        LibSubAccount.DecodedSubAccountId memory decoded = subAccountId.decodeSubAccountId();
        require(decoded.account != address(0), "T=0");
        require(_hasAsset(decoded.collateralId), "Lst"); // the asset is not LiSTed
        require(_hasAsset(decoded.assetId), "Lst"); // the asset is not LiSTed
        require(amount != 0, "A=0");
        require(collateralPrice != 0, "P=0");
        require(assetPrice != 0, "P=0");

        Asset storage asset = _storage.assets[decoded.assetId];
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(!asset.isStable, "Stb");
        require(asset.isTradable, "Trd");
        require(asset.isOpenable, "Opn");
        require(decoded.isLong || asset.isShortable, "Sht");
        if (decoded.isLong) {
            require(asset.totalLongPosition + amount <= asset.maxLongPositionSize, "MxP");
        } else {
            require(asset.totalShortPosition + amount <= asset.maxShortPositionSize, "MxP");
        }
        // fee & funding
        uint96 feeUsd = _getFeeUsd(subAccount, asset, decoded.isLong, amount, assetPrice);
        {
            subAccount.entryFunding = _getCumulativeFunding(asset, decoded.isLong);
            uint96 feeCollateral = uint256(feeUsd).wdiv(collateralPrice).safeUint96();
            require(subAccount.collateral >= feeCollateral, "Fee");
            subAccount.collateral -= feeCollateral;
            Asset storage collateral = _storage.assets[decoded.collateralId];
            collateral.collectedFee += feeCollateral;
            collateral.spotLiquidity += feeCollateral;
            emit CollectedFee(decoded.collateralId, feeCollateral);
        }

        // position
        {
            (, uint96 pnlUsd) = _positionPnlUsd(asset, subAccount, decoded.isLong, amount, assetPrice);
            uint96 newSize = subAccount.size + amount;
            if (pnlUsd == 0) {
                subAccount.entryPrice = assetPrice;
            } else {
                subAccount.entryPrice = ((uint256(subAccount.entryPrice) *
                    uint256(subAccount.size) +
                    uint256(assetPrice) *
                    uint256(amount)) / newSize).safeUint96();
            }
            subAccount.size = newSize;
        }

        subAccount.lastIncreasedTime = _blockTimestamp();
        emit OpenPosition(
            subAccountId,
            decoded.account,
            decoded.collateralId,
            decoded.assetId,
            amount,
            decoded.isLong,
            assetPrice,
            subAccount.entryPrice,
            feeUsd
        );
        // total
        _increaseTotalSize(asset, decoded.isLong, amount, assetPrice);
        // post check
        require(_isAccountImSafe(subAccount, decoded.assetId, decoded.isLong, collateralPrice, assetPrice), "!IM");
    }

    struct ClosePositionContext {
        LibSubAccount.DecodedSubAccountId id;
        uint96 totalFeeUsd;
        uint96 paidFeeUsd;
    }

    function closePosition(
        bytes32 subAccountId,
        uint96 amount,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external onlyOrderBook {
        ClosePositionContext memory ctx;
        ctx.id = subAccountId.decodeSubAccountId();
        require(ctx.id.account != address(0), "T=0");
        require(_hasAsset(ctx.id.collateralId), "Lst"); // the asset is not LiSTed
        require(_hasAsset(ctx.id.assetId), "Lst"); // the asset is not LiSTed
        require(amount != 0, "A=0");
        require(collateralPrice != 0, "P=0");
        require(assetPrice != 0, "P=0");
        Asset storage asset = _storage.assets[ctx.id.assetId];
        if (ctx.id.isLong && !asset.useStableTokenForProfit) {
            profitAssetId = ctx.id.assetId;
            profitAssetPrice = assetPrice;
        } else {
            require(_isStable(profitAssetId), "Stb");
            require(profitAssetPrice != 0, "P=0");
        }

        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(!asset.isStable, "Stb");
        require(asset.isTradable, "Trd");
        require(ctx.id.isLong || asset.isShortable, "Sht");
        require(amount <= subAccount.size, "A>S");
        // total
        _decreaseTotalSize(asset, ctx.id.isLong, amount);
        // fee & funding
        ctx.totalFeeUsd = _getFeeUsd(subAccount, asset, ctx.id.isLong, amount, assetPrice);
        subAccount.entryFunding = _getCumulativeFunding(asset, ctx.id.isLong);
        // realize pnl
        {
            (bool hasProfit, uint96 pnlUsd) = _positionPnlUsd(asset, subAccount, ctx.id.isLong, amount, assetPrice);
            if (hasProfit) {
                ctx.paidFeeUsd = _realizeProfit(
                    ctx.id.account,
                    pnlUsd,
                    ctx.totalFeeUsd,
                    _storage.assets[profitAssetId],
                    profitAssetPrice
                );
            } else {
                _realizeLoss(subAccount, _storage.assets[ctx.id.collateralId], collateralPrice, pnlUsd, true);
            }
            subAccount.size -= amount;
            if (subAccount.size == 0) {
                subAccount.entryPrice = 0;
                subAccount.entryFunding = 0;
                subAccount.lastIncreasedTime = 0;
            }
        }
        // ignore fees if can not afford
        if (ctx.totalFeeUsd > ctx.paidFeeUsd) {
            uint96 feeCollateral = uint256(ctx.totalFeeUsd - ctx.paidFeeUsd).wdiv(collateralPrice).safeUint96();
            feeCollateral = LibMath.min(feeCollateral, subAccount.collateral);
            subAccount.collateral -= feeCollateral;
            Asset storage collateral = _storage.assets[ctx.id.collateralId];
            collateral.collectedFee += feeCollateral;
            collateral.spotLiquidity += feeCollateral;
            emit CollectedFee(ctx.id.collateralId, feeCollateral);
            ctx.paidFeeUsd += uint256(feeCollateral).wmul(collateralPrice).safeUint96();
        }
        emit ClosePosition(
            subAccountId,
            ctx.id.account,
            ctx.id.collateralId,
            ctx.id.assetId,
            amount,
            ctx.id.isLong,
            assetPrice,
            subAccount.entryPrice,
            ctx.paidFeeUsd
        );
        // post check
        require(_isAccountMmSafe(subAccount, ctx.id.assetId, ctx.id.isLong, collateralPrice, assetPrice), "!MM");
    }

    struct LiquidateContext {
        LibSubAccount.DecodedSubAccountId id;
        uint96 totalFeeUsd;
        uint96 paidFeeUsd;
    }

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external onlyOrderBook {
        LiquidateContext memory ctx;
        ctx.id = subAccountId.decodeSubAccountId();
        require(ctx.id.account != address(0), "T=0");
        require(_hasAsset(ctx.id.collateralId), "Lst"); // the asset is not LiSTed
        require(_hasAsset(ctx.id.assetId), "Lst"); // the asset is not LiSTed
        require(collateralPrice != 0, "P=0");
        require(assetPrice != 0, "P=0");
        Asset storage asset = _storage.assets[ctx.id.assetId];
        if (ctx.id.isLong && !asset.useStableTokenForProfit) {
            profitAssetId = ctx.id.assetId;
            profitAssetPrice = assetPrice;
        } else {
            require(_isStable(profitAssetId), "Stb");
            require(profitAssetPrice != 0, "P=0");
        }

        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(!asset.isStable, "Stb");
        require(asset.isTradable, "Trd");
        require(ctx.id.isLong || asset.isShortable, "Sht"); // FIXME: should this be removed?
        require(subAccount.size > 0, "A=0");
        // total
        _decreaseTotalSize(asset, ctx.id.isLong, subAccount.size);
        // fee & funding
        ctx.totalFeeUsd = _getFeeUsd(subAccount, asset, ctx.id.isLong, subAccount.size, assetPrice);
        // should mm unsafe
        (bool hasProfit, uint96 pnlUsd) = _positionPnlUsd(
            asset,
            subAccount,
            ctx.id.isLong,
            subAccount.size,
            assetPrice
        );
        require(
            !_isAccountSafe(subAccount, collateralPrice, assetPrice, asset.maintenanceMarginRate, hasProfit, pnlUsd),
            "MM"
        );
        // realize pnl
        uint96 oldPositionSize = subAccount.size;
        {
            if (hasProfit) {
                ctx.paidFeeUsd = _realizeProfit(
                    ctx.id.account,
                    pnlUsd,
                    ctx.totalFeeUsd,
                    _storage.assets[profitAssetId],
                    profitAssetPrice
                );
            } else {
                _realizeLoss(subAccount, _storage.assets[ctx.id.collateralId], collateralPrice, pnlUsd, false);
            }
            subAccount.size = 0;
            subAccount.entryPrice = 0;
            subAccount.entryFunding = 0;
            subAccount.lastIncreasedTime = 0;
        }
        // ignore fees if can not afford
        if (ctx.totalFeeUsd > ctx.paidFeeUsd) {
            uint96 feeCollateral = uint256(ctx.totalFeeUsd - ctx.paidFeeUsd).wdiv(collateralPrice).safeUint96();
            feeCollateral = LibMath.min(feeCollateral, subAccount.collateral);
            subAccount.collateral -= feeCollateral;
            Asset storage collateral = _storage.assets[ctx.id.collateralId];
            collateral.collectedFee += feeCollateral;
            collateral.spotLiquidity += feeCollateral;
            emit CollectedFee(ctx.id.collateralId, feeCollateral);
            ctx.paidFeeUsd += uint256(feeCollateral).wmul(collateralPrice).safeUint96();
        }
        emit Liquidate(
            subAccountId,
            ctx.id.account,
            ctx.id.collateralId,
            ctx.id.assetId,
            oldPositionSize,
            ctx.id.isLong,
            assetPrice,
            ctx.paidFeeUsd
        );
    }

    struct WithdrawProfitContext {
        LibSubAccount.DecodedSubAccountId id;
        uint96 totalFeeUsd;
    }

    /**
     *  long : (exit - entry) size = (exit - entry') size + withdrawUSD
     *  short: (entry - exit) size = (entry' - exit) size + withdrawUSD
     */
    function withdrawProfit(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external onlyOrderBook {
        require(rawAmount != 0, "A=0");
        WithdrawProfitContext memory ctx;
        ctx.id = subAccountId.decodeSubAccountId();
        require(ctx.id.account != address(0), "T=0");
        require(_hasAsset(ctx.id.collateralId), "Lst"); // the asset is not LiSTed
        require(_hasAsset(ctx.id.assetId), "Lst"); // the asset is not LiSTed
        require(collateralPrice != 0, "P=0");
        require(assetPrice != 0, "P=0");
        Asset storage asset = _storage.assets[ctx.id.assetId];
        if (ctx.id.isLong && !asset.useStableTokenForProfit) {
            profitAssetId = ctx.id.assetId;
            profitAssetPrice = assetPrice;
        } else {
            require(_isStable(profitAssetId), "Stb");
            require(profitAssetPrice != 0, "P=0");
        }

        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(!asset.isStable, "Stb");
        require(asset.isTradable, "Trd");
        require(ctx.id.isLong || asset.isShortable, "Sht");
        require(subAccount.size > 0, "A=0");
        // fee & funding
        uint96 totalFeeUsd = _getFundingFeeUsd(subAccount, asset, ctx.id.isLong);
        subAccount.entryFunding = _getCumulativeFunding(asset, ctx.id.isLong);
        // withdraw
        uint96 deltaUsd = _storage.assets[profitAssetId].toWad(rawAmount);
        deltaUsd = uint256(deltaUsd).wmul(profitAssetPrice).safeUint96();
        deltaUsd += totalFeeUsd;
        // profit
        {
            (bool hasProfit, uint96 pnlUsd) = _positionPnlUsd(
                asset,
                subAccount,
                ctx.id.isLong,
                subAccount.size,
                assetPrice
            );
            require(hasProfit, "U<0");
            require(pnlUsd >= deltaUsd, "U<W");
        }
        _realizeProfit(
            ctx.id.account,
            uint256(deltaUsd).safeUint96(),
            totalFeeUsd,
            _storage.assets[profitAssetId],
            profitAssetPrice
        );
        // new entry price
        if (ctx.id.isLong) {
            subAccount.entryPrice += uint256(deltaUsd).wdiv(subAccount.size).safeUint96();
            asset.averageLongPrice += uint256(deltaUsd).wdiv(asset.totalLongPosition).safeUint96();
        } else {
            subAccount.entryPrice -= uint256(deltaUsd).wdiv(subAccount.size).safeUint96();
            asset.averageShortPrice -= uint256(deltaUsd).wdiv(asset.totalShortPosition).safeUint96();
        }
        require(_isAccountImSafe(subAccount, ctx.id.assetId, ctx.id.isLong, collateralPrice, assetPrice), "!IM");
        emit WithdrawProfit(
            subAccountId,
            ctx.id.account,
            ctx.id.collateralId,
            ctx.id.assetId,
            rawAmount,
            ctx.id.isLong,
            assetPrice,
            subAccount.entryPrice,
            ctx.totalFeeUsd
        );
    }

    function _increaseTotalSize(
        Asset storage asset,
        bool isLong,
        uint96 amount,
        uint96 price
    ) internal {
        if (isLong) {
            uint96 newPosition = asset.totalLongPosition + amount;
            asset.averageLongPrice = ((uint256(asset.averageLongPrice) *
                uint256(asset.totalLongPosition) +
                uint256(price) *
                uint256(amount)) / uint256(newPosition)).safeUint96();
            asset.totalLongPosition = newPosition;
        } else {
            uint96 newPosition = asset.totalShortPosition + amount;
            asset.averageShortPrice = ((uint256(asset.averageShortPrice) *
                uint256(asset.totalShortPosition) +
                uint256(price) *
                uint256(amount)) / uint256(newPosition)).safeUint96();
            asset.totalShortPosition = newPosition;
        }
    }

    function _decreaseTotalSize(
        Asset storage asset,
        bool isLong,
        uint96 amount
    ) internal {
        if (isLong) {
            asset.totalLongPosition -= amount;
        } else {
            asset.totalShortPosition -= amount;
        }
    }

    function _realizeProfit(
        address trader,
        uint96 pnlUsd,
        uint96 feeUsd,
        Asset storage profitAsset,
        uint96 profitAssetPrice
    ) internal returns (uint96 paidFeeUsd) {
        paidFeeUsd = LibMath.min(feeUsd, pnlUsd);
        // pnl
        pnlUsd -= paidFeeUsd;
        if (pnlUsd > 0) {
            uint96 profitCollateral = uint256(pnlUsd).wdiv(profitAssetPrice).safeUint96();
            // transfer profit token
            uint96 spot = LibMath.min(profitCollateral, profitAsset.spotLiquidity);
            if (spot > 0) {
                profitAsset.spotLiquidity -= spot; // already reserved fee
                uint256 rawAmount = profitAsset.toRaw(spot);
                profitAsset.transferOut(trader, rawAmount, _storage.weth);
            }
            // debt
            {
                uint96 debtWadAmount = profitCollateral - spot;
                if (debtWadAmount > 0) {
                    profitAsset.issueMuxToken(trader, uint256(debtWadAmount));
                }
            }
        }
        // fee
        if (paidFeeUsd > 0) {
            uint96 paidFeeCollateral = uint256(paidFeeUsd).wdiv(profitAssetPrice).safeUint96();
            profitAsset.collectedFee += paidFeeCollateral;
            emit CollectedFee(profitAsset.id, paidFeeCollateral);
        }
    }

    function _realizeLoss(
        SubAccount storage subAccount,
        Asset storage collateral,
        uint96 collateralPrice,
        uint96 pnlUsd,
        bool isThrowBankrupt
    ) internal {
        if (pnlUsd == 0) {
            return;
        }
        uint96 pnlCollateral = uint256(pnlUsd).wdiv(collateralPrice).safeUint96();
        if (isThrowBankrupt) {
            require(subAccount.collateral >= pnlCollateral, "M=0");
        } else {
            pnlCollateral = LibMath.min(pnlCollateral, subAccount.collateral);
        }
        subAccount.collateral -= pnlCollateral;
        collateral.spotLiquidity += pnlCollateral;
    }
}
