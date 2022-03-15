// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "../interfaces/ILiquidityPool.sol";
import "./Types.sol";
import "./LmDexProxy.sol";
import "./LmStorage.sol";
import "./LmAdmin.sol";
import "./LmGetter.sol";
import { AdminParamsType } from "../core/Types.sol";

contract LiquidityManager is LmStorage, LmDexProxy, LmAdmin, LmGetter {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize(address pool) external initializer {
        __SafeOwnable_init();
        _pool = ILiquidityPool(pool);
    }

    function getDexRewards(uint8 dexId)
        external
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        return _getDexRewards(dexId);
    }

    function getDexFees(uint8 dexId) external returns (address[] memory rewardTokens, uint256[] memory rewardAmounts) {
        return _getDexFees(dexId);
    }

    function getDexRedeemableAmounts(uint8 dexId, uint256 shareAmount) external returns (uint256[] memory amounts) {
        return _getDexRedeemableAmounts(dexId, shareAmount);
    }

    function addDexLiquidity(
        uint8 dexId,
        uint256[] calldata maxAmounts,
        uint256 deadline
    ) external onlyOwner returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(maxAmounts.length > 0, "NoAmounts");
        require(_hasConnector(dexId), "DexNotExists");
        DexSpotConfiguration storage spotConfig = _dexSpotConfigs[dexId];
        _transferFromLiquidityPool(spotConfig.assetIds, maxAmounts);
        return _addDexLiquidity(dexId, maxAmounts, deadline);
    }

    function removeDexLiquidity(
        uint8 dexId,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external onlyOwner returns (uint256[] memory removedAmounts) {
        require(shareAmount > 0, "ZeroShareAmount");
        require(minAmounts.length > 0, "NoAmounts");
        require(_hasConnector(dexId), "DexNotExists");

        DexSpotConfiguration storage spotConfig = _dexSpotConfigs[dexId];
        removedAmounts = _removeDexLiquidity(dexId, shareAmount, minAmounts, deadline);
        require(spotConfig.assetIds.length == removedAmounts.length, "ParamsLengthMismatch");
        _transferToLiquidityPool(spotConfig.assetIds, removedAmounts);
    }

    function returnMuxLiquidity(uint8[] calldata assetIds, uint256[] calldata amounts) external onlyOwner {
        require(assetIds.length > 0, "NoAssets");
        require(assetIds.length == amounts.length, "ParamsLengthMismatch");
        _transferToLiquidityPool(assetIds, amounts);
    }

    function _transferFromLiquidityPool(uint8[] memory assetIds, uint256[] memory amounts) internal {
        require(assetIds.length == amounts.length, "ParamsLengthMismatch");
        _pool.setParams(AdminParamsType.WithdrawLiquidity, abi.encode(assetIds, amounts));
    }

    function _transferToLiquidityPool(uint8[] memory assetIds, uint256[] memory amounts) internal {
        uint256 length = assetIds.length;
        for (uint256 i = 0; i < length; i++) {
            IERC20Upgradeable asset = IERC20Upgradeable(_getAssetAddress(assetIds[i]));
            asset.safeTransfer(address(_pool), amounts[i]);
        }
        _pool.setParams(AdminParamsType.DepositLiquidity, abi.encode(assetIds));
    }

    function transferToChain(uint256 chainId) external onlyOwner {
        // TODO: bridge token to another chain
    }
}
