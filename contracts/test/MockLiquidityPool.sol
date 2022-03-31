// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ILiquidityPool.sol";

import "hardhat/console.sol";

contract MockLiquidityPool is ILiquidityPool {
    mapping(uint8 => address) public mockAssets;

    function setAssetAddress(uint8 assetId, address tokenAddress) external {
        mockAssets[assetId] = tokenAddress;
    }

    function getAssetAddress(uint8 assetId) external view returns (address) {
        return mockAssets[assetId];
    }

    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint32 mlpFeeRate
    ) external {}

    function removeLiquidity(
        address trader,
        uint96 mlpAmount, // NOTE: OrderBook should transfer mlpAmount to me
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint32 mlpFeeRate
    ) external {}

    function openPosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external {}

    function closePosition(
        bytes32 subAccountId,
        uint96 amount,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external {}

    function depositCollateral(bytes32 subAccountId) external {}

    function withdrawCollateral(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external {}

    function withdrawAllCollateral(bytes32 subAccountId) external {}

    function withdrawProfit(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external {}

    function getAssetInfo(uint8 assetId) external view returns (Asset memory) {}

    function transferLiquidityOut(uint8[] memory assetIds, uint256[] memory amounts) external {
        for (uint256 i = 0; i < assetIds.length; i++) {
            IERC20(mockAssets[assetIds[i]]).transfer(msg.sender, amounts[i]);
        }
    }

    function transferLiquidityIn(uint8[] memory assetIds, uint256[] memory amounts) external {}

    function getSubAccount(bytes32 subAccountId)
        external
        view
        returns (
            uint96 collateral,
            uint96 size,
            uint32 lastIncreasedTime,
            uint96 entryPrice,
            uint128 entryFunding
        )
    {}

    function updateFundingState(
        uint32 stableUtilization, // 1e5
        uint8[] calldata unstableTokenIds,
        uint32[] calldata unstableUtilizations
    ) external {}

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external {}

    function redeemMuxToken(
        address trader,
        uint8 tokenId,
        uint96 muxTokenAmount // NOTE: OrderBook SHOULD transfer muxTokenAmount to LiquidityPool
    ) external {}
}
