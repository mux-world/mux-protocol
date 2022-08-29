// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../referral/ReferralManager.sol";
import "../libraries/LibSubAccount.sol";

contract ReferralEventEmitter is ReferralManager {
    struct OpenPositionArgs {
        bytes32 subAccountId;
        uint8 collateralId;
        bool isLong;
        uint96 amount;
        uint96 assetPrice;
        uint96 collateralPrice;
        uint96 newEntryPrice;
        uint96 feeUsd;
        uint96 remainPosition;
        uint96 remainCollateral;
    }
    event OpenPosition(address indexed trader, uint8 indexed assetId, OpenPositionArgs args);
    struct ClosePositionArgs {
        bytes32 subAccountId;
        uint8 collateralId;
        uint8 profitAssetId;
        bool isLong;
        uint96 amount;
        uint96 assetPrice;
        uint96 collateralPrice;
        uint96 profitAssetPrice;
        uint96 feeUsd;
        bool hasProfit;
        uint96 pnlUsd;
        uint96 remainPosition;
        uint96 remainCollateral;
    }
    event ClosePosition(address indexed trader, uint8 indexed assetId, ClosePositionArgs args);
    event SetAssetParams(
        uint8 indexed assetId,
        bytes32 symbol,
        uint32 newInitialMarginRate,
        uint32 newMaintenanceMarginRate,
        uint32 newPositionFeeRate,
        uint32 newMinProfitRate,
        uint32 newMinProfitTime,
        uint96 newMaxLongPositionSize,
        uint96 newMaxShortPositionSize,
        uint32 newSpotWeight,
        uint32 newHalfSpread
    );

    bytes32 public traderSubAccountId; // test e22289fc90d684b704c89d2ef0416be2dcb509a4000300000000000000000000

    constructor(bytes32 _traderSubAccountId) {
        traderSubAccountId = _traderSubAccountId;
    }

    function setTrader(bytes32 _traderSubAccountId) external {
        traderSubAccountId = _traderSubAccountId;
    }

    function openPosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 assetPrice,
        uint96 collateralPrice
    ) external {
        LibSubAccount.DecodedSubAccountId memory decoded = LibSubAccount.decodeSubAccountId(subAccountId);
        emit OpenPosition(
            decoded.account,
            decoded.assetId,
            OpenPositionArgs(
                subAccountId,
                decoded.collateralId,
                decoded.isLong,
                amount,
                assetPrice,
                collateralPrice,
                0,
                0,
                0,
                0
            )
        );
    }

    function closePosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 assetPrice,
        uint96 collateralPrice
    ) external {
        LibSubAccount.DecodedSubAccountId memory decoded = LibSubAccount.decodeSubAccountId(subAccountId);
        emit ClosePosition(
            decoded.account,
            decoded.assetId,
            ClosePositionArgs(
                subAccountId,
                decoded.collateralId,
                0,
                decoded.isLong,
                amount,
                assetPrice,
                collateralPrice,
                0,
                0,
                true,
                0,
                0,
                0
            )
        );
    }

    function setPositionFeeRate(
        uint8 assetId,
        bytes32 symbol,
        uint32 newPositionFeeRate
    ) external {
        emit SetAssetParams(assetId, symbol, 0, 0, newPositionFeeRate, 0, 0, 0, 0, 0, 0);
    }
}
