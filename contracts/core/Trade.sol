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

    event AddLiquidity(
        address indexed trader,
        uint8 indexed tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 mlpAmount
    );
    event RemoveLiquidity(
        address indexed trader,
        uint8 indexed tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 mlpAmount,
        uint256 tokenRawAmount
    );
    event OpenPosition(
        bytes32 indexed subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint8 assetId,
        uint96 amount,
        bool isLong,
        uint96 assetPrice,
        uint96 entryPrice,
        uint96 feeUsd
    );
    event ClosePosition(
        bytes32 indexed subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint8 assetId,
        uint96 amount,
        bool isLong,
        uint96 assetPrice,
        uint96 entryPrice,
        uint96 feeUsd
    );
    event Liquidate(
        bytes32 indexed subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint8 assetId,
        uint96 amount,
        bool isLong,
        uint96 assetPrice,
        uint96 feeUsd
    );
    event WithdrawProfit(
        bytes32 indexed subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint8 assetId,
        uint256 withdrawRawAmount,
        bool isLong,
        uint96 assetPrice,
        uint96 entryPrice,
        uint96 feeUsd
    );
    event UpdateFundingRate(
        uint8 tokenId,
        bool isStable,
        uint32 fundingRate, // 1e5
        uint128 accumulateFunding
    );

    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice
    ) external onlyOrderBook {
        require(trader != address(0), "InvalidTrader");
        require(_hasAsset(tokenId), "TokenNotListed");
        require(tokenPrice != 0, "ZeroTokenPrice");
        require(mlpPrice != 0, "ZeroTokenPrice");

        Asset storage token = _storage.assets[tokenId];
        uint256 rawAmount = token.calcTransferredBalance();
        require(rawAmount != 0, "NotTokenDeposited");
        uint96 wadAmount = token.toWad(rawAmount);

        uint96 mlpAmount = ((uint256(wadAmount) * uint256(tokenPrice)) / uint256(mlpPrice)).safeUint96();
        IERC20Upgradeable(_storage.mlp).transfer(trader, mlpAmount);
        token.liquidityBalance += wadAmount;
        _storage.liquidityLocks[trader] = uint32(_blockTimestamp()) + _storage.liquidityLockPeriod;

        emit AddLiquidity(trader, tokenId, tokenPrice, mlpPrice, mlpAmount);
    }

    function removeLiquidity(
        address trader,
        uint96 mlpAmount, // NOTE: OrderBook should transfer mlpAmount to me
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice
    ) external onlyOrderBook {
        require(trader != address(0), "InvalidTrader");
        require(_hasAsset(tokenId), "TokenNotListed");
        require(tokenPrice != 0, "ZeroTokenPrice");
        require(mlpPrice != 0, "ZeroTokenPrice");
        require(mlpAmount != 0, "ZeroAmount");
        require(_blockTimestamp() >= _storage.liquidityLocks[trader], "TimeLockNotSuppressed");

        Asset storage token = _storage.assets[tokenId];
        uint96 wadAmount = ((uint256(mlpAmount) * uint256(mlpPrice)) / uint256(tokenPrice)).safeUint96();
        uint256 rawAmount = token.toRaw(wadAmount);
        require(token.liquidityBalance >= wadAmount, "InsufficientLiquidity");

        token.liquidityBalance -= wadAmount;
        token.transferOut(trader, rawAmount);

        emit RemoveLiquidity(trader, tokenId, tokenPrice, mlpPrice, mlpAmount, rawAmount);
    }

    function openPosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external onlyOrderBook {
        LibSubAccount.DecodedSubAccountId memory decoded = subAccountId.decodeSubAccountId();
        require(decoded.account != address(0), "InvalidTrader");
        require(_hasAsset(decoded.collateralId), "CollateralNotListed");
        require(_hasAsset(decoded.assetId), "AssetNotListed");
        require(amount != 0, "InvalidAmount");
        require(collateralPrice != 0, "ZeroCollateralPrice");
        require(assetPrice != 0, "ZeroAssetPrice");

        Asset storage asset = _storage.assets[decoded.assetId];
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(!asset.isStable, "CannotTradeStable");
        require(asset.isTradable, "TradeDisabled");
        require(asset.isOpenable, "OpenDisabled");
        require(decoded.isLong || asset.isShortable, "ShortDisabled");
        if (decoded.isLong) {
            require(asset.totalLongPosition + amount <= asset.maxLongPositionSize, "MaxPositionExceeded");
        } else {
            require(asset.totalShortPosition + amount <= asset.maxShortPositionSize, "MaxPositionExceeded");
        }
        // fee & funding
        uint96 feeUsd = _getFeeUsd(subAccount, asset, decoded.isLong, amount, assetPrice);
        {
            (subAccount.entryFunding, ) = _getFundingState(asset, decoded.isLong);
            uint96 feeCollateral = uint256(feeUsd).wdiv(collateralPrice).safeUint96();
            require(subAccount.collateral >= feeCollateral, "InsufficientCollateralForFee");
            subAccount.collateral -= feeCollateral;
            _storage.assets[decoded.collateralId].collectedFee += feeCollateral;
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
        require(
            _isAccountImSafe(subAccount, decoded.assetId, decoded.isLong, collateralPrice, assetPrice),
            "AccountImUnsafe"
        );
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
        require(ctx.id.account != address(0), "InvalidTrader");
        require(_hasAsset(ctx.id.collateralId), "CollateralNotListed");
        require(_hasAsset(ctx.id.assetId), "AssetNotListed");
        require(amount != 0, "InvalidAmount");
        require(collateralPrice != 0, "ZeroCollateralPrice");
        require(assetPrice != 0, "ZeroAssetPrice");
        Asset storage asset = _storage.assets[ctx.id.assetId];
        if (ctx.id.isLong && !asset.useStableTokenForProfit) {
            profitAssetId = ctx.id.assetId;
            profitAssetPrice = assetPrice;
        } else {
            require(_isStable(profitAssetId), "InvalidProfitAsset");
            require(profitAssetPrice != 0, "ZeroProfitPrice");
        }

        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(!asset.isStable, "TradingStable");
        require(asset.isTradable, "TradingDisabled");
        require(ctx.id.isLong || asset.isShortable, "ShortDisabled");
        require(amount <= subAccount.size, "AmountTooLarge");
        // total
        _decreaseTotalSize(asset, ctx.id.isLong, amount);
        // fee & funding
        ctx.totalFeeUsd = _getFeeUsd(subAccount, asset, ctx.id.isLong, amount, assetPrice);
        (subAccount.entryFunding, ) = _getFundingState(asset, ctx.id.isLong);
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
            _storage.assets[ctx.id.collateralId].collectedFee += feeCollateral;
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
        require(
            _isAccountMmSafe(subAccount, ctx.id.assetId, ctx.id.isLong, collateralPrice, assetPrice),
            "AccountMmUnsafe"
        );
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
        require(ctx.id.account != address(0), "InvalidTrader");
        require(_hasAsset(ctx.id.collateralId), "CollateralNotListed");
        require(_hasAsset(ctx.id.assetId), "AssetNotListed");
        require(collateralPrice != 0, "ZeroCollateralPrice");
        require(assetPrice != 0, "ZeroAssetPrice");
        Asset storage asset = _storage.assets[ctx.id.assetId];
        if (ctx.id.isLong && !asset.useStableTokenForProfit) {
            profitAssetId = ctx.id.assetId;
            profitAssetPrice = assetPrice;
        } else {
            require(_isStable(profitAssetId), "InvalidProfitAsset");
            require(profitAssetPrice != 0, "ZeroProfitPrice");
        }

        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(!asset.isStable, "TradingStable");
        require(asset.isTradable, "TradingDisabled");
        require(ctx.id.isLong || asset.isShortable, "ShortDisabled"); // FIXME: should this be removed?
        require(subAccount.size > 0, "EmptyPosition");
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
            "AccountMmSafe"
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
            _storage.assets[ctx.id.collateralId].collectedFee += feeCollateral;
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
        require(rawAmount != 0, "ZeroAmount");
        WithdrawProfitContext memory ctx;
        ctx.id = subAccountId.decodeSubAccountId();
        require(ctx.id.account != address(0), "InvalidTrader");
        require(_hasAsset(ctx.id.collateralId), "CollateralNotListed");
        require(_hasAsset(ctx.id.assetId), "AssetNotListed");
        require(collateralPrice != 0, "ZeroCollateralPrice");
        require(assetPrice != 0, "ZeroAssetPrice");
        Asset storage asset = _storage.assets[ctx.id.assetId];
        if (ctx.id.isLong && !asset.useStableTokenForProfit) {
            profitAssetId = ctx.id.assetId;
            profitAssetPrice = assetPrice;
        } else {
            require(_isStable(profitAssetId), "InvalidProfitAsset");
            require(profitAssetPrice != 0, "ZeroProfitPrice");
        }

        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(!asset.isStable, "TradingStable");
        require(asset.isTradable, "TradingDisabled");
        require(ctx.id.isLong || asset.isShortable, "ShortDisabled");
        require(subAccount.size > 0, "EmptyPosition");
        // fee & funding
        uint96 totalFeeUsd = _getFundingFeeUsd(subAccount, asset, ctx.id.isLong);
        (subAccount.entryFunding, ) = _getFundingState(asset, ctx.id.isLong);
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
            require(hasProfit, "NotProfitToWithdraw");
            require(pnlUsd >= deltaUsd, "InsufficientPnl");
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
        require(
            _isAccountImSafe(subAccount, ctx.id.assetId, ctx.id.isLong, collateralPrice, assetPrice),
            "AccountImUnsafe"
        );
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

    function updateFundingState(
        uint8[] calldata tokenIds,
        uint32[] calldata fundingRates // 1e5
    ) external onlyOrderBook {
        bool isStableUpdated = false;
        uint256 fundingRateCount = fundingRates.length;
        for (uint256 i = 0; i < fundingRateCount; i++) {
            Asset storage asset = _storage.assets[tokenIds[i]];
            if (asset.isStable) {
                if (isStableUpdated) {
                    continue;
                }
                isStableUpdated = true;
            }
            (, uint32 lastFundingTime) = _getFundingState(asset, !asset.isStable);
            if (lastFundingTime == 0) {
                _accumulateFundingState(
                    asset,
                    0,
                    (_blockTimestamp() / _storage.fundingInterval) * _storage.fundingInterval
                );
                continue;
            }
            if (lastFundingTime + _storage.fundingInterval >= _blockTimestamp()) {
                continue;
            }
            uint32 nextFundingTime = (_blockTimestamp() / _storage.fundingInterval) * _storage.fundingInterval;
            uint32 timespan = nextFundingTime - lastFundingTime;
            uint32 newFundingRate = _truncateFundingRate(asset, fundingRates[i]);
            (uint128 newCumulativeFunding, ) = _accumulateFundingState(
                asset,
                ((uint256(newFundingRate) * uint256(timespan) * 1e13) / FUNDING_PERIOD).safeUint128(),
                nextFundingTime
            );
            emit UpdateFundingRate(tokenIds[i], asset.isStable, newFundingRate, newCumulativeFunding);
        }
    }

    function _accumulateFundingState(
        Asset storage asset,
        uint128 cumulativeFunding,
        uint32 lastFundingTime
    ) internal returns (uint128, uint32) {
        FundingState storage state;
        if (asset.isStable) {
            state = _storage.shortFunding;
        } else {
            state = asset.longFunding;
        }
        state.cumulativeFunding += cumulativeFunding;
        state.lastFundingTime = lastFundingTime;
        return (state.cumulativeFunding, state.lastFundingTime);
    }

    function _truncateFundingRate(Asset storage asset, uint32 fundingRate)
        internal
        view
        returns (uint32 newFundingRate)
    {
        FundingConfiguration storage configuration;
        if (asset.isStable) {
            configuration = _storage.shortFundingConfiguration;
        } else {
            configuration = asset.longFundingConfiguration;
        }
        newFundingRate = LibMath.min32(fundingRate, configuration.limitRate8H);
        newFundingRate = LibMath.max32(newFundingRate, configuration.baseRate8H);
    }

    function _realizeProfit(
        address trader,
        uint96 pnlUsd,
        uint96 feeUsd,
        Asset storage profitAsset,
        uint96 profitAssetPrice
    ) internal returns (uint96 deductUsd) {
        deductUsd = LibMath.min(feeUsd, pnlUsd);
        // pnl
        pnlUsd -= deductUsd;
        if (pnlUsd > 0) {
            uint96 profitCollateral = uint256(pnlUsd).wdiv(profitAssetPrice).safeUint96();
            // transfer profit token
            uint96 spot = LibMath.min(profitCollateral, profitAsset.liquidityBalance);
            if (spot > 0) {
                profitAsset.liquidityBalance -= spot;
                uint256 rawAmount = profitAsset.toRaw(spot);
                profitAsset.transferOut(trader, rawAmount);
            }
            // debt
            {
                uint96 debtWadAmount = profitCollateral - spot;
                if (debtWadAmount > 0) {
                    profitAsset.issueMux(trader, uint256(debtWadAmount));
                }
            }
        }
        // fee
        if (deductUsd > 0) {
            uint96 deductCollateral = uint256(deductUsd).wdiv(profitAssetPrice).safeUint96();
            profitAsset.collectedFee += deductCollateral;
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
            require(subAccount.collateral >= pnlCollateral, "Bankrupt");
        } else {
            pnlCollateral = LibMath.min(pnlCollateral, subAccount.collateral);
        }
        subAccount.collateral -= pnlCollateral;
        collateral.liquidityBalance += pnlCollateral;
    }
}
