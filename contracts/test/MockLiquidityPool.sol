// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ILiquidityPool.sol";

contract MockLiquidityPool is ILiquidityPool {
    mapping(uint8 => address) public mockAssetAddress;
    mapping(uint8 => uint32) public mockMinProfitTime;
    mapping(uint8 => uint32) public mockMinProfitRate;
    mapping(bytes32 => SubAccount) public mockSubAccounts;

    function setAssetAddress(uint8 assetId, address tokenAddress) external {
        mockAssetAddress[assetId] = tokenAddress;
    }

    function setAssetParams(uint8 assetId, uint32 newMinProfitTime, uint32 newMinProfitRate) external {
        mockMinProfitTime[assetId] = newMinProfitTime;
        mockMinProfitRate[assetId] = newMinProfitRate;
    }

    function getAssetAddress(uint8 assetId) external view returns (address) {
        return mockAssetAddress[assetId];
    }

    function getAssetInfo(uint8 assetId) external view returns (Asset memory asset) {
        asset.tokenAddress = mockAssetAddress[assetId];
        asset.minProfitTime = mockMinProfitTime[assetId];
        asset.minProfitRate = mockMinProfitRate[assetId];
    }

    function getAllAssetInfo() external view returns (Asset[] memory) {}

    function getLiquidityPoolStorage()
        external
        view
        returns (
            // [0] shortFundingBaseRate8H
            // [1] shortFundingLimitRate8H
            // [2] lastFundingTime
            // [3] fundingInterval
            // [4] liquidityBaseFeeRate
            // [5] liquidityDynamicFeeRate
            // [6] sequence. note: will be 0 after 0xffffffff
            // [7] strictStableDeviation
            uint32[8] memory u32s,
            // [0] mlpPriceLowerBound
            // [1] mlpPriceUpperBound
            uint96[2] memory u96s
        )
    {}

    function getSubAccount(
        bytes32 subAccountId
    )
        external
        view
        returns (uint96 collateral, uint96 size, uint32 lastIncreasedTime, uint96 entryPrice, uint128 entryFunding)
    {
        SubAccount storage subAccount = mockSubAccounts[subAccountId];
        collateral = subAccount.collateral;
        size = subAccount.size;
        lastIncreasedTime = subAccount.lastIncreasedTime;
        entryPrice = subAccount.entryPrice;
        entryFunding = subAccount.entryFunding;
    }

    function withdrawAllCollateral(bytes32 subAccountId) external {}

    function depositCollateral(
        bytes32 subAccountId,
        uint256 rawAmount // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
    ) external {}

    function withdrawCollateral(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external {}

    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint256 rawAmount, // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue
    ) external returns (uint96) {}

    function removeLiquidity(
        address trader,
        uint96 mlpAmount, // NOTE: OrderBook SHOULD transfer mlpAmount mlp to LiquidityPool
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue
    ) external returns (uint256) {}

    function openPosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 /* collateralPrice */,
        uint96 assetPrice
    ) external returns (uint96) {
        mockSubAccounts[subAccountId] = SubAccount({
            collateral: amount,
            size: amount,
            lastIncreasedTime: uint32(block.timestamp),
            entryPrice: assetPrice,
            entryFunding: 0
        });
        return assetPrice;
    }

    function closePosition(
        bytes32,
        uint96,
        uint8, // only used when !isLong
        uint96,
        uint96 assetPrice,
        uint96 // only used when !isLong
    ) external pure returns (uint96 tradingPrice) {
        return assetPrice;
    }

    function transferLiquidityOut(uint8[] memory assetIds, uint256[] memory amounts) external {
        for (uint256 i = 0; i < assetIds.length; i++) {
            IERC20(mockAssetAddress[assetIds[i]]).transfer(msg.sender, amounts[i]);
        }
    }

    function transferLiquidityIn(uint8[] memory assetIds, uint256[] memory amounts) external {}

    function updateFundingState(
        uint32 stableUtilization, // 1e5
        uint8[] calldata unstableTokenIds,
        uint32[] calldata unstableUtilizations, // 1e5
        uint96[] calldata unstablePrices
    ) external {}

    function liquidate(
        bytes32,
        uint8, // only used when !isLong
        uint96,
        uint96 assetPrice,
        uint96 // only used when !isLong
    ) external pure returns (uint96) {
        return assetPrice;
    }

    function redeemMuxToken(
        address trader,
        uint8 tokenId,
        uint96 muxTokenAmount // NOTE: OrderBook SHOULD transfer muxTokenAmount to LiquidityPool
    ) external {}

    function claimBrokerGasRebate(address receiver) external returns (uint256 rawAmount) {}

    function rebalance(
        address rebalancer,
        uint8 tokenId0,
        uint8 tokenId1,
        uint96 rawAmount0,
        uint96 maxRawAmount1,
        bytes32 userData,
        uint96 price0,
        uint96 price1
    ) external {}
}
