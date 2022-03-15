// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../core/Types.sol";

interface ILiquidityPool {
    function getAssetAddress(uint8 assetId) external view returns (address);

    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice
    ) external;

    function removeLiquidity(
        address trader,
        uint96 mlpAmount,
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice
    ) external;

    function openPosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external;

    function closePosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint8 profitAssetId
    ) external;

    function depositCollateral(bytes32 subAccountId) external;

    function withdrawCollateral(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external;

    function withdrawAllCollateral(bytes32 subAccountId) external;

    function withdrawProfit(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint8 profitAssetId
    ) external;

    function getAssetInfo(uint8 assetId) external view returns (Asset memory);

    function setParams(AdminParamsType paramType, bytes calldata params) external;

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

    function updateFundingState(uint8[] calldata tokenIds, uint32[] calldata fundingRates) external;
}
