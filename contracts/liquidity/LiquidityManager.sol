// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "../interfaces/ILiquidityPool.sol";
import "./Types.sol";
import "./LmDexProxy.sol";
import "./LmStorage.sol";
import "./LmAdmin.sol";
import "./LmBridge.sol";
import "./LmTransfer.sol";
import "./LmGetter.sol";

contract LiquidityManager is LmStorage, LmTransfer, LmDexProxy, LmAdmin, LmBridge, LmGetter {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event AddLiquidity(uint8 indexed dexId, uint256[] addedAmounts, uint256 liquidityAmount);
    event RemoveLiquidity(uint8 indexed dexId, uint256 shareAmount, uint256[] removedAmounts);
    event ClaimDexRewards(uint8 indexed dexId, address[] rewardTokens, uint256[] rewardAmounts);

    function initialize(address pool) external initializer {
        __SafeOwnable_init();
        _pool = ILiquidityPool(pool);
    }

    function addDexLiquidity(
        uint8 dexId,
        uint256[] calldata maxAmounts,
        uint256 deadline
    ) external onlyOwner returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(maxAmounts.length > 0, "Mty"); // argument array is eMpTY
        require(_hasConnector(dexId), "Lst"); // the asset is not LiSTed
        DexSpotConfiguration storage spotConfig = _dexSpotConfigs[dexId];
        _transferFromLiquidityPool(spotConfig.assetIds, maxAmounts);
        (addedAmounts, liquidityAmount) = _addDexLiquidity(dexId, maxAmounts, deadline);
        emit AddLiquidity(dexId, addedAmounts, liquidityAmount);
    }

    function removeDexLiquidity(
        uint8 dexId,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external onlyOwner returns (uint256[] memory removedAmounts) {
        require(shareAmount > 0, "A=0");
        require(minAmounts.length > 0, "Mty"); // argument array is eMpTY
        require(_hasConnector(dexId), "Lst"); // the asset is not LiSTed
        DexSpotConfiguration storage spotConfig = _dexSpotConfigs[dexId];
        removedAmounts = _removeDexLiquidity(dexId, shareAmount, minAmounts, deadline);
        require(spotConfig.assetIds.length == removedAmounts.length, "Len"); // LENgth of 2 arguments does not match
        _transferToLiquidityPool(spotConfig.assetIds, removedAmounts);
        emit RemoveLiquidity(dexId, shareAmount, removedAmounts);
    }

    function claimDexReward(uint8 dexId)
        external
        onlyOwner
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        require(_hasConnector(dexId), "Lst"); // the asset is not LiSTed
        (rewardTokens, rewardAmounts) = _claimDexRewards(dexId);
        emit ClaimDexRewards(dexId, rewardTokens, rewardAmounts);
    }

    function returnMuxLiquidity(uint8[] calldata assetIds, uint256[] calldata amounts) external onlyOwner {
        require(assetIds.length > 0, "Mty"); // argument array is eMpTY
        require(assetIds.length == amounts.length, "Len"); // Length of 2 arguments does not match
        _transferToLiquidityPool(assetIds, amounts);
    }

    function transferToChain(
        uint256 chainId,
        uint8[] memory assetIds,
        uint256[] memory amounts
    ) external onlyOwner {
        require(_hasBridge(chainId), "!CB");
        BridgeConfiguration storage bridgeConfig = _bridgeConfigs[chainId];
        _transferFromLiquidityPool(assetIds, amounts);
        for (uint256 i = 0; i < assetIds.length; i++) {
            _bridgeTransfer(bridgeConfig, _getAssetAddress(assetIds[i]), amounts[i]);
        }
    }
}
