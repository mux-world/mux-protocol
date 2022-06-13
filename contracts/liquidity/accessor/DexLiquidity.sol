// SPDX-License-Identifier: GPL-2.0-or-later
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
    mapping(address => bool) public brokers;

    event SetBroker(address indexed broker, bool enable);
    event SetSlippage(uint32 slippage);

    constructor(address liquidityManager_) SafeOwnable() {
        manager = liquidityManager_;
    }

    /**
     * @notice Set the slippage when adding liquidity. Slippage is a protection against the chain congestion.
     */
    function setSlippage(uint32 newSlippage) external onlyOwner {
        require(slippage != newSlippage, "SNC"); // slippage is not changed
        slippage = newSlippage;
        emit SetSlippage(newSlippage);
    }

    /**
     * @notice Enable or disable an address as broker. Broker is able to call add / remove liquidity methods.
     */
    function setBroker(address broker, bool enable) external onlyOwner {
        require(brokers[broker] != enable, "BNC"); // broker status is not changed
        brokers[broker] = enable;
        emit SetBroker(broker, enable);
    }

    /**
     * @notice This method is a wrapper for the method of `LiquidityManager` with the same name.
     *         Return all the dex configurations.
     */
    function getAllDexSpotConfiguration() external view returns (DexSpotConfiguration[] memory) {
        return ILiquidityManager(manager).getAllDexSpotConfiguration();
    }

    /**
     * @notice This method is a wrapper for the method of `LiquidityManager` with the same name.
     *         Return the specified dex configurations.
     */
    function getDexSpotConfiguration(uint8 dexId) external view returns (DexSpotConfiguration memory) {
        return ILiquidityManager(manager).getDexSpotConfiguration(dexId);
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

    function getDexLpBalance(uint8 dexId) external returns (uint256 lpBalance) {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 getLpBalanceId = LibUtils.toBytes32("getLpBalance");
        if (_manager.hasDexCall(dexId, getLpBalanceId)) {
            bytes memory lpBalanceRaw = _manager.moduleCall(
                CallContext({ dexId: dexId, methodId: getLpBalanceId, params: "" })
            );
            lpBalance = abi.decode(lpBalanceRaw, (uint256));
        } else {
            lpBalance = 0;
        }
    }

    function getDexFees(uint8 dexId) external returns (uint256[] memory fees) {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 getFeesId = LibUtils.toBytes32("getFees");
        if (_manager.hasDexCall(dexId, getFeesId)) {
            bytes memory lpBalanceRaw = _manager.moduleCall(
                CallContext({ dexId: dexId, methodId: getFeesId, params: "" })
            );
            fees = abi.decode(lpBalanceRaw, (uint256[]));
        } else {
            uint256 length = ILiquidityManager(manager).getDexSpotConfiguration(dexId).assetIds.length;
            fees = new uint256[](length);
        }
    }

    function getDexRewards(uint8 dexId) external returns (address[] memory tokens, uint256[] memory rewardAmounts) {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 getRewardsId = LibUtils.toBytes32("getRewards");
        if (_manager.hasDexCall(dexId, getRewardsId)) {
            bytes memory result = _manager.moduleCall(
                CallContext({ dexId: dexId, methodId: getRewardsId, params: "" })
            );
            (tokens, rewardAmounts) = abi.decode(result, (address[], uint256[]));
        }
    }

    function claimDexRewards(uint8 dexId) external {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 claimRewardsId = LibUtils.toBytes32("claimRewards");
        _manager.moduleCall(CallContext({ dexId: dexId, methodId: claimRewardsId, params: "" }));
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
    ) external returns (uint256[] memory addedAmounts, uint256 shareAmount) {
        require(msg.sender == owner() || brokers[msg.sender], "SND");
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
    ) external returns (uint256[] memory removedAmounts) {
        require(msg.sender == owner() || brokers[msg.sender], "SND");
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
