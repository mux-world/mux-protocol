// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/ILiquidityManager.sol";
import "../../libraries/LibUtils.sol";

import "../../components/SafeOwnable.sol";
import "../Types.sol";

/**
 * @title DexLiquidity is a wrapper of liquidity managing methods for `LiquidityManager`.
 *        It has limited privileges.
 */
contract DexLiquidity is SafeOwnable {
    uint32 public slippage = 500;
    address public manager;

    constructor(address liquidityManager_) SafeOwnable() {
        manager = liquidityManager_;
    }

    /**
     * @notice Set the slippage when adding liquidity. Slippage is a protection against the chain congestion.
     */
    function setSlippage(uint32 slippage_) external onlyOwner {
        slippage = slippage_;
    }

    /**
     * @notice This method is a wrapper for the method of `LiquidityManager` with the same name.
     *         Return all the dex configurations.
     */
    function getAllDexSpotConfiguration() external view returns (DexSpotConfiguration[] memory) {
        return ILiquidityManager(manager).getAllDexSpotConfiguration();
    }

    /**
     * @notice Read the liquidity of the dex and the corresponding spot quantity. The amount of spot is
     *         converted using the formulas provide by dex. It may changes over time until removed.
     * @param dexId The id of dex.
     * @return liquidities A array represents the spot amount can be returned if all the provided liquidities are removed.
     * @return lpBalance The balance of lp tokens.
     */
    function getDexLiquidity(uint8 dexId) external returns (uint256[] memory liquidities, uint256 lpBalance) {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 getLpBalanceId = LibUtils.toBytes32("getLpBalance");
        bytes32 getSpotAmountsId = LibUtils.toBytes32("getSpotAmounts");
        if (_manager.hasDexCall(dexId, getLpBalanceId) && _manager.hasDexCall(dexId, getSpotAmountsId)) {
            bytes memory lpBalanceRaw = _manager.moduleCall(
                CallContext({ dexId: dexId, methodId: getLpBalanceId, params: "" })
            );
            bytes memory liquiditiesRaw = _manager.moduleCall(
                CallContext({ dexId: dexId, methodId: getSpotAmountsId, params: lpBalanceRaw })
            );
            lpBalance = abi.decode(lpBalanceRaw, (uint256));
            liquidities = abi.decode(liquiditiesRaw, (uint256[]));
        } else {
            lpBalance = 0;
            liquidities = new uint256[](_manager.getDexSpotConfiguration(dexId).assetIds.length);
        }
    }

    /**
     * @notice Withdraw assets from LiquidityPool then add to given dex.
     *         Before calling this method, the connector for given dex must be set.
     * @param dexId The id of the dex.
     * @param maxAmounts The maximum amount of assets to add to dex. The order of amounts follows the configuration of `assetIds` of dex.
     * @param deadline The deadline passed to the underlying dex contract. If the dex does not support timeout, this field is omitted.
     * @return addedAmounts The amounts of assets are actually added to the dex. These amounts should always be less or equal to the maxAmounts params.
     * @return shareAmount The amount of share for added liquidities.
     */
    function addDexLiquidity(
        uint8 dexId,
        uint256[] calldata maxAmounts,
        uint256 deadline
    ) external onlyOwner returns (uint256[] memory addedAmounts, uint256 shareAmount) {
        require(maxAmounts.length > 0, "MTY"); // argument array is eMpTY
        ILiquidityManager(manager).moduleCall(
            CallContext({
                dexId: 0,
                methodId: LibUtils.toBytes32("transferFromPoolByDex"),
                params: abi.encode(dexId, maxAmounts)
            })
        );
        uint256 length = maxAmounts.length;
        uint256[] memory minAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            minAmounts[i] = (maxAmounts[i] * (100000 - slippage)) / 100000;
        }
        bytes memory result = ILiquidityManager(manager).moduleCall(
            CallContext({
                dexId: dexId,
                methodId: LibUtils.toBytes32("addLiquidity"),
                params: abi.encode(maxAmounts, minAmounts, deadline)
            })
        );
        (addedAmounts, shareAmount) = abi.decode(result, (uint256[], uint256));
    }

    /**
     * @notice Remove liquidities from the given dex then send them back to LiquidityPool.
     *         Before calling this method, the connector for given dex must be set.
     * @param dexId the id of the dex.
     * @param shareAmount The amount of shares to remove from the dex.
     * @param minAmounts The minimal amount of assets to get back from the dex.
     * @param deadline The deadline passed to the underlying dex contract. If the dex does not support timeout, this field is omitted.
     * @return removedAmounts The amounts of assets are actually removed from the dex. These amounts should always be greater or equal to the minAmounts params.
     */
    function removeDexLiquidity(
        uint8 dexId,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external onlyOwner returns (uint256[] memory removedAmounts) {
        require(shareAmount > 0, "A=0"); // Amount Is Zero
        require(minAmounts.length > 0, "MTY"); // argument array is eMpTY
        bytes memory result = ILiquidityManager(manager).moduleCall(
            CallContext({
                dexId: dexId,
                methodId: LibUtils.toBytes32("removeLiquidity"),
                params: abi.encode(shareAmount, minAmounts, deadline)
            })
        );
        (removedAmounts) = abi.decode(result, (uint256[]));
        ILiquidityManager(manager).moduleCall(
            CallContext({
                dexId: 0,
                methodId: LibUtils.toBytes32("transferToPoolByDex"),
                params: abi.encode(dexId, removedAmounts)
            })
        );
    }
}
