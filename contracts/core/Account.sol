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
    event ClaimMLP(address indexed lp, uint96 mlpAmount);

    function depositCollateral(bytes32 subAccountId) external {
        LibSubAccount.DecodedSubAccountId memory decoded = subAccountId.decodeSubAccountId();
        require(decoded.account != address(0), "T=0");
        require(_hasAsset(decoded.collateralId), "Lst"); // the asset is not LiSTed
        require(_hasAsset(decoded.assetId), "Lst"); // the asset is not LiSTed

        SubAccount storage subAccount = _storage.accounts[subAccountId];
        Asset storage collateral = _storage.assets[decoded.collateralId];
        uint256 rawAmount = collateral.calcTransferredBalance();
        require(rawAmount != 0, "A=0");
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
        require(rawAmount != 0, "A=0");
        LibSubAccount.DecodedSubAccountId memory decoded = subAccountId.decodeSubAccountId();
        require(decoded.account != address(0), "T=0");
        require(_hasAsset(decoded.collateralId), "Lst"); // the asset is not LiSTed
        require(_hasAsset(decoded.assetId), "Lst"); // the asset is not LiSTed
        require(collateralPrice != 0, "P=0");
        require(assetPrice != 0, "P=0");

        Asset storage asset = _storage.assets[decoded.assetId];
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        // fee & funding
        uint96 feeUsd = _getFundingFeeUsd(subAccount, asset, decoded.isLong);
        {
            subAccount.entryFunding = _getCumulativeFunding(asset, decoded.isLong);
            uint96 feeCollateral = uint256(feeUsd).wdiv(collateralPrice).safeUint96();
            require(subAccount.collateral >= feeCollateral, "Fee");
            subAccount.collateral -= feeCollateral;
            _storage.assets[decoded.collateralId].collectedFee += feeCollateral;
        }
        // withdraw
        Asset storage collateral = _storage.assets[decoded.collateralId];
        uint96 wadAmount = collateral.toWad(rawAmount);
        require(subAccount.collateral >= wadAmount, "C<W");
        subAccount.collateral = subAccount.collateral - wadAmount;
        collateral.transferOut(decoded.account, rawAmount, _storage.weth);
        require(_isAccountImSafe(subAccount, decoded.assetId, decoded.isLong, collateralPrice, assetPrice), "!IM");

        emit WithdrawCollateral(subAccountId, decoded.account, decoded.collateralId, rawAmount, wadAmount);
    }

    // Trader can withdraw all collateral only when position = 0
    function withdrawAllCollateral(bytes32 subAccountId) external {
        LibSubAccount.DecodedSubAccountId memory decoded = subAccountId.decodeSubAccountId();
        require(msg.sender == decoded.account || msg.sender == _storage.orderBook, "Bok");
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(subAccount.size == 0, "S>0");
        require(subAccount.collateral > 0, "C=0");

        Asset storage collateral = _storage.assets[decoded.collateralId];
        uint96 wadAmount = subAccount.collateral;
        uint256 rawAmount = collateral.toRaw(wadAmount);
        subAccount.collateral = 0;
        collateral.transferOut(decoded.account, rawAmount, _storage.weth);
        emit WithdrawCollateral(subAccountId, decoded.account, decoded.collateralId, rawAmount, wadAmount);
    }

    function claimMLP() external {
        address lp = msg.sender;
        LiquidityLock storage lock = _storage.liquidityLocks[lp];
        require(_blockTimestamp() >= lock.lastAddedTime + _storage.liquidityLockPeriod, "Lck");
        uint96 mlpAmount = lock.pendingMLP;
        lock.pendingMLP = 0;
        lock.lastAddedTime = 0;
        IERC20Upgradeable(_storage.mlp).transfer(lp, mlpAmount);
        emit ClaimMLP(lp, mlpAmount);
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
        require(assetPrice > 0, "P=0");
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
        uint128 cumulativeFunding = _getCumulativeFunding(asset, isLong);
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

    function _getCumulativeFunding(Asset storage asset, bool isLong) internal view returns (uint128) {
        return isLong ? asset.longCumulativeFunding : _storage.shortCumulativeFunding;
    }
}
