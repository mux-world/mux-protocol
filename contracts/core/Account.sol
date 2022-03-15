// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../libraries/LibSubAccount.sol";
import "../libraries/LibMath.sol";
import "../libraries/LibAsset.sol";

import "./Storage.sol";

contract Account is Storage {
    using LibMath for uint256;
    using LibSubAccount for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using LibAsset for Asset;

    event DepositCollateral(
        bytes32 indexed subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint256 rawAmount,
        uint96 wadAmount
    );
    event WithdrawCollateral(
        bytes32 indexed subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint256 rawAmount,
        uint96 wadAmount
    );

    function depositCollateral(bytes32 subAccountId) external onlyOrderBook {
        LibSubAccount.DecodedSubAccountId memory decoded = subAccountId.decodeSubAccountId();
        require(decoded.account != address(0), "InvalidTrader");
        require(_hasAsset(decoded.collateralId), "CollateralNotListed");
        require(_hasAsset(decoded.assetId), "AssetNotListed");

        SubAccount storage subAccount = _storage.accounts[subAccountId];
        Asset storage collateral = _storage.assets[decoded.collateralId];
        uint256 rawAmount = collateral.calcTransferredBalance();
        require(rawAmount != 0, "NoTokenDeposited");
        uint96 wadAmount = collateral.toWad(rawAmount);

        subAccount.collateral += wadAmount;

        emit DepositCollateral(subAccountId, decoded.account, decoded.collateralId, rawAmount, wadAmount);
    }

    function withdrawCollateral(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external onlyOrderBook {
        require(rawAmount != 0, "ZeroAmount");
        LibSubAccount.DecodedSubAccountId memory decoded = subAccountId.decodeSubAccountId();
        require(decoded.account != address(0), "InvalidTrader");
        require(_hasAsset(decoded.collateralId), "CollateralNotListed");
        require(_hasAsset(decoded.assetId), "AssetNotListed");
        require(collateralPrice != 0, "ZeroCollateralPrice");
        require(assetPrice != 0, "ZeroAssetPrice");

        Asset storage asset = _storage.assets[decoded.assetId];
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        // fee & funding
        uint96 feeUsd = _getFundingFeeUsd(subAccount, asset, decoded.isLong);
        {
            (subAccount.entryFunding, ) = _getFundingState(asset, decoded.isLong);
            uint96 feeCollateral = uint256(feeUsd).wdiv(collateralPrice).safeUint96();
            require(subAccount.collateral >= feeCollateral, "InsufficientCollateralForFee");
            subAccount.collateral -= feeCollateral;
            _storage.assets[decoded.collateralId].collectedFee += feeCollateral;
        }
        // withdraw
        Asset storage collateral = _storage.assets[decoded.collateralId];
        uint96 wadAmount = collateral.toWad(rawAmount);
        require(subAccount.collateral >= wadAmount, "InsufficientCollateralForWithdrawal");
        subAccount.collateral = subAccount.collateral - wadAmount;
        collateral.transferOut(decoded.account, rawAmount);
        require(
            _isAccountImSafe(subAccount, decoded.assetId, decoded.isLong, collateralPrice, assetPrice),
            "AccountImUnsafe"
        );

        emit WithdrawCollateral(subAccountId, decoded.account, decoded.collateralId, rawAmount, wadAmount);
    }

    // Trader can withdraw all collateral only when position = 0
    function withdrawAllCollateral(bytes32 subAccountId) external {
        LibSubAccount.DecodedSubAccountId memory decoded = subAccountId.decodeSubAccountId();
        require(msg.sender == decoded.account || msg.sender == _storage.orderBook, "WithdrawerMustBeTraderOrOrderBook");
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(subAccount.size == 0, "OnlyWhenEmptyPosition");
        require(subAccount.collateral > 0, "EmptyCollateral");

        Asset storage collateral = _storage.assets[decoded.collateralId];
        uint96 wadAmount = subAccount.collateral;
        uint256 rawAmount = collateral.toRaw(wadAmount);
        subAccount.collateral = 0;
        collateral.transferOut(decoded.account, rawAmount);
        emit WithdrawCollateral(subAccountId, decoded.account, decoded.collateralId, rawAmount, wadAmount);
    }

    function _positionPnlUsd(
        Asset storage asset,
        SubAccount storage subAccount,
        bool isLong,
        uint96 amount,
        uint96 assetPrice
    ) internal view returns (bool hasProfit, uint96 pnlUsd) {
        if (amount == 0) {
            return (false, 0);
        }
        require(assetPrice > 0, "InvalidAssetPrice");
        hasProfit = isLong ? assetPrice > subAccount.entryPrice : assetPrice < subAccount.entryPrice;
        uint96 priceDelta = assetPrice >= subAccount.entryPrice
            ? assetPrice - subAccount.entryPrice
            : subAccount.entryPrice - assetPrice;
        if (
            hasProfit &&
            _blockTimestamp() < subAccount.lastIncreasedTime + asset.minProfitTime &&
            priceDelta < uint256(subAccount.entryPrice).wmul(asset.minProfitRate).safeUint96()
        ) {
            hasProfit = false;
            return (false, 0);
        }
        pnlUsd = uint256(priceDelta).wmul(amount).safeUint96();
    }

    // NOTE: settle funding before this function
    function _isAccountImSafe(
        SubAccount storage subAccount,
        uint32 assetId,
        bool isLong,
        uint96 collateralPrice,
        uint96 assetPrice
    ) internal view returns (bool) {
        Asset storage asset = _storage.assets[assetId];
        (bool hasProfit, uint96 pnlUsd) = _positionPnlUsd(asset, subAccount, isLong, subAccount.size, assetPrice);
        return _isAccountSafe(subAccount, collateralPrice, assetPrice, asset.initialMarginRate, hasProfit, pnlUsd);
    }

    // NOTE: settle funding before this function
    function _isAccountMmSafe(
        SubAccount storage subAccount,
        uint32 assetId,
        bool isLong,
        uint96 collateralPrice,
        uint96 assetPrice
    ) internal view returns (bool) {
        Asset storage asset = _storage.assets[assetId];
        (bool hasProfit, uint96 pnlUsd) = _positionPnlUsd(asset, subAccount, isLong, subAccount.size, assetPrice);
        return _isAccountSafe(subAccount, collateralPrice, assetPrice, asset.maintenanceMarginRate, hasProfit, pnlUsd);
    }

    // NOTE: settle funding before this function
    function _isAccountSafe(
        SubAccount storage subAccount,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint32 marginRate,
        bool hasProfit,
        uint96 pnlUsd
    ) internal view returns (bool) {
        uint256 thresholdUsd = (uint256(subAccount.size) * uint256(assetPrice) * uint256(marginRate)) / 1e18 / 1e5;
        uint256 collateralUsd = uint256(subAccount.collateral).wmul(collateralPrice);
        // break down "collateral_usd +/- pnl_usd >= threshold_usd>= 0"
        if (hasProfit) {
            return collateralUsd + pnlUsd >= thresholdUsd;
        }
        if (collateralUsd < pnlUsd) {
            return false;
        }
        return collateralUsd - pnlUsd >= thresholdUsd;
    }

    function _getFeeUsd(
        SubAccount storage subAccount,
        Asset storage asset,
        bool isLong,
        uint96 amount,
        uint96 assetPrice
    ) internal view returns (uint96) {
        return _getFundingFeeUsd(subAccount, asset, isLong) + _getPositionFeeUsd(asset, amount, assetPrice);
    }

    function _getFundingFeeUsd(
        SubAccount storage subAccount,
        Asset storage asset,
        bool isLong
    ) internal view returns (uint96) {
        if (subAccount.size == 0) {
            return 0;
        }
        (uint128 cumulativeFunding, ) = _getFundingState(asset, isLong);
        return uint256(cumulativeFunding - subAccount.entryFunding).wmul(subAccount.size).safeUint96();
    }

    function _getPositionFeeUsd(
        Asset storage asset,
        uint96 amount,
        uint96 assetPrice
    ) internal view returns (uint96) {
        if (amount == 0) {
            return 0;
        }
        uint256 feeUsd = ((uint256(assetPrice) * uint256(asset.positionFeeRate)) * uint256(amount)) / 1e5 / 1e18;
        return feeUsd.safeUint96();
    }

    function _getFundingState(Asset storage asset, bool isLong) internal view returns (uint128, uint32) {
        return
            isLong
                ? (asset.longFunding.cumulativeFunding, asset.longFunding.lastFundingTime)
                : (_storage.shortFunding.cumulativeFunding, _storage.shortFunding.lastFundingTime);
    }
}
