// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

contract Events {
    //////////////////////////////////////////////////////////////////////////////////////
    //                                   trade
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
    event CollectedFee(uint8 tokenId, uint96 fee);

    //////////////////////////////////////////////////////////////////////////////////////
    //                                   liquidity
    event AddLiquidity(
        address indexed trader,
        uint8 indexed tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 mlpAmount,
        uint96 fee
    );
    event RemoveLiquidity(
        address indexed trader,
        uint8 indexed tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 mlpAmount,
        uint256 tokenRawAmount,
        uint96 fee
    );
    event UpdateFundingRate(
        uint8 tokenId, // if isStable, tokenId will always be 0
        bool isStable,
        uint32 fundingRate, // 1e5
        uint128 accumulateFunding
    );

    //////////////////////////////////////////////////////////////////////////////////////
    //                                   admin
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
    event SetFundingParams(uint8 tokenId, uint32 newBaseRate8H, uint32 newLimitRate8H);
    event SetFundingInterval(uint32 oldFundingInterval, uint32 newFundingInterval);
    event SetLiquidityLockPeriod(uint32 oldLockPeriod, uint32 newLockPeriod);
    event TransferLiquidity(address indexed sender, address indexed recipient, uint8 assetId, uint256 amount);
}
