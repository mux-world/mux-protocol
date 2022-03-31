// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

contract Events {
    //////////////////////////////////////////////////////////////////////////////////////
    //                                   trade
    event OpenPosition(
        bytes32 subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint8 indexed assetId,
        bool isLong,
        uint96 amount,
        uint96 assetPrice,
        uint96 entryPrice,
        uint96 feeUsd
    );
    event ClosePosition(
        bytes32 subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint8 indexed assetId,
        bool isLong,
        uint96 amount,
        uint96 assetPrice,
        uint96 entryPrice,
        uint96 feeUsd,
        bool hasProfit,
        uint96 pnlUsd
    );
    event Liquidate(
        bytes32 subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint8 indexed assetId,
        bool isLong,
        uint96 amount,
        uint96 assetPrice,
        uint96 entryPrice,
        uint96 feeUsd,
        bool hasProfit,
        uint96 pnlUsd
    );
    event WithdrawProfit(
        bytes32 subAccountId,
        address indexed trader,
        uint8 collateralId,
        uint8 indexed assetId,
        bool isLong,
        uint256 withdrawRawAmount,
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
        uint96 fee
    );
    event UpdateFundingRate(
        uint8 indexed tokenId, // if isStable, tokenId will always be 0
        bool isStable,
        uint32 fundingRate, // 1e5
        uint128 accumulateFunding
    );
    event IssueMuxToken(
        uint8 indexed tokenId, // if isStable, tokenId will always be 0
        bool isStable,
        uint96 muxTokenAmount
    );
    event RedeemMuxToken(address trader, uint8 tokenId, uint96 muxTokenAmount);

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
        uint32 newSpotWeight
    );
    event SetAssetFlags(
        uint8 indexed assetId,
        bool isTradable,
        bool isOpenable,
        bool isShortable,
        bool useStableTokenForProfit
    );
    event SetReferenceOracle(
        uint8 indexed assetId,
        uint8 referenceOracleType,
        address referenceOracle,
        uint32 referenceDeviation
    );
    event SetFundingParams(uint8 indexed assetId, uint32 newBaseRate8H, uint32 newLimitRate8H);
    event SetFundingInterval(uint32 oldFundingInterval, uint32 newFundingInterval);
    event SetMlpPriceRange(uint96 newLowerBound, uint96 newUpperBound);
    event TransferLiquidity(address indexed sender, address indexed recipient, uint8 assetId, uint256 amount);
}
