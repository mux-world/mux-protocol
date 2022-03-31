// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../core/Types.sol";

interface ILiquidityPool {
    /////////////////////////////////////////////////////////////////////////////////
    //                                 getters

    function getAssetAddress(uint8 assetId) external view returns (address);

    function getAssetInfo(uint8 assetId) external view returns (Asset memory);

    function getSubAccount(bytes32 subAccountId)
        external
        view
        returns (
            uint96 collateral,
            uint96 size,
            uint32 lastIncreasedTime,
            uint96 entryPrice,
            uint128 entryFunding
        );

    /////////////////////////////////////////////////////////////////////////////////
    //                             for Trader / Broker

    function depositCollateral(bytes32 subAccountId) external;

    function withdrawAllCollateral(bytes32 subAccountId) external;

    /////////////////////////////////////////////////////////////////////////////////
    //                                 only Broker

    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint32 mlpFeeRate
    ) external;

    function removeLiquidity(
        address trader,
        uint96 mlpAmount, // NOTE: OrderBook should transfer mlpAmount to me
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint32 mlpFeeRate
    ) external;

    function openPosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external;

    /**
     * @notice Close a position
     *
     * @param  subAccountId     check LibSubAccount.encodeSubAccountId for detail.
     * @param  amount           position size.
     * @param  profitAssetId    for long position (unless asset.useStable is true), ignore this argument;
     *                          for short position, the profit asset should be one of the stable coin.
     * @param  collateralPrice  price of subAccount.collateral.
     * @param  assetPrice       price of subAccount.asset.
     * @param  profitAssetPrice price of profitAssetId. ignore this argument if profitAssetId is ignored.
     */
    function closePosition(
        bytes32 subAccountId,
        uint96 amount,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external;

    function withdrawCollateral(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external;

    function withdrawProfit(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external;

    /**
     * @notice Broker can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     * @param  stableUtilization    Stable coin utilization
     * @param  unstableTokenIds     All unstable Asset id(s) MUST be passed in order. ex: 1, 2, 5, 6, ...
     * @param  unstableUtilizations Unstable Asset utilizations
     */
    function updateFundingState(
        uint32 stableUtilization, // 1e5
        uint8[] calldata unstableTokenIds,
        uint32[] calldata unstableUtilizations // 1e5
    ) external;

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external;

    function redeemMuxToken(
        address trader,
        uint8 tokenId,
        uint96 muxTokenAmount // NOTE: OrderBook SHOULD transfer muxTokenAmount to LiquidityPool
    ) external;

    /////////////////////////////////////////////////////////////////////////////////
    //                            only LiquidityManager

    function transferLiquidityOut(uint8[] memory assetIds, uint256[] memory amounts) external;

    function transferLiquidityIn(uint8[] memory assetIds, uint256[] memory amounts) external;
}
