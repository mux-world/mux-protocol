// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ILiquidityPool.sol";

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
        uint96 mlpPrice
    ) external {}

    function removeLiquidity(
        address trader,
        uint96 mlpAmount,
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice
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
        uint96 collateralPrice,
        uint96 assetPrice,
        uint8 profitAssetId
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
        uint96 collateralPrice,
        uint96 assetPrice,
        uint8 profitAssetId
    ) external {}

    function getAssetInfo(uint8 assetId) external view returns (Asset memory) {}

    function setParams(AdminParamsType paramType, bytes calldata params) external {
        if (paramType == AdminParamsType.WithdrawLiquidity) {
            (uint8[] memory assetIds, uint256[] memory amounts) = abi.decode(params, (uint8[], uint256[]));
            for (uint256 i = 0; i < assetIds.length; i++) {
                IERC20(mockAssets[assetIds[i]]).transfer(msg.sender, amounts[i]);
            }
        } else if (paramType == AdminParamsType.DepositLiquidity) {
            // uint8[] memory assetIds = abi.decode(params, (uint8[]));
        } else {
            revert("UnknownKey");
        }
    }

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

    function updateFundingState(uint8[] calldata tokenIds, uint32[] calldata fundingRates) external {}
}
