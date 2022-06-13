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
    address public manager;
    mapping(address => bool) public brokers;

    event SetBroker(address indexed broker, bool enable);

    constructor(address liquidityManager_) SafeOwnable() {
        manager = liquidityManager_;
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
    function getAllDexSpotConfiguration() external returns (DexSpotConfiguration[] memory) {
        return ILiquidityManager(manager).getAllDexSpotConfiguration();
    }

    /**
     * @notice This method is a wrapper for the method of `LiquidityManager` with the same name.
     *         Return the specified dex configurations.
     */
    function getDexSpotConfiguration(uint8 dexId) external returns (DexSpotConfiguration memory) {
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
            bytes memory lpBalanceRaw = _manager.callDexModule(dexId, getLpBalanceId, "");
            bytes memory liquiditiesRaw = _manager.callDexModule(dexId, getSpotAmountsId, lpBalanceRaw);
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
            bytes memory lpBalanceRaw = _manager.callDexModule(dexId, getLpBalanceId, "");
            lpBalance = abi.decode(lpBalanceRaw, (uint256));
        } else {
            lpBalance = 0;
        }
    }

    function getDexFees(uint8 dexId)
        external
        returns (
            address[] memory rewardTokens,
            uint256[] memory collectedFeeAmounts,
            uint256[] memory pendingFeeAmounts
        )
    {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 getFeesId = LibUtils.toBytes32("getFees");
        if (_manager.hasDexCall(dexId, getFeesId)) {
            bytes memory lpBalanceRaw = _manager.callDexModule(dexId, getFeesId, "");
            (rewardTokens, collectedFeeAmounts, pendingFeeAmounts) = abi.decode(
                lpBalanceRaw,
                (address[], uint256[], uint256[])
            );
        } else {
            uint256 length = ILiquidityManager(manager).getDexSpotConfiguration(dexId).assetIds.length;
            rewardTokens = new address[](length);
            collectedFeeAmounts = new uint256[](length);
            pendingFeeAmounts = new uint256[](length);
        }
    }

    function getDexRewards(uint8 dexId) external returns (address[] memory tokens, uint256[] memory rewardAmounts) {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 getRewardsId = LibUtils.toBytes32("getRewards");
        if (_manager.hasDexCall(dexId, getRewardsId)) {
            bytes memory result = _manager.callDexModule(dexId, getRewardsId, "");
            (tokens, rewardAmounts) = abi.decode(result, (address[], uint256[]));
        }
    }

    function claimDexRewards(uint8 dexId) external {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 claimRewardsId = LibUtils.toBytes32("claimRewards");
        if (_manager.hasDexCall(dexId, claimRewardsId)) {
            _manager.callDexModule(dexId, claimRewardsId, "");
        }
    }

    function getDexValidationData(uint8 dexId, uint256[] memory minAmounts) public virtual returns (bytes memory data) {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 getValidationDataId = LibUtils.toBytes32("getValidationData");
        if (_manager.hasDexCall(dexId, getValidationDataId)) {
            bytes memory result = _manager.callDexModule(dexId, getValidationDataId, abi.encode(minAmounts));
            data = abi.decode(result, (bytes));
        }
    }

    function getDexPrice(
        uint8 dexId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public virtual returns (uint256 price) {
        ILiquidityManager _manager = ILiquidityManager(manager);
        bytes32 getPriceId = LibUtils.toBytes32("getPrice");
        if (_manager.hasDexCall(dexId, getPriceId)) {
            bytes memory result = _manager.callDexModule(dexId, getPriceId, abi.encode(tokenIn, tokenOut, amountIn));
            price = abi.decode(result, (uint256));
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
        uint256 deadline,
        bytes memory validationData
    ) external returns (uint256[] memory addedAmounts, uint256 shareAmount) {
        require(msg.sender == owner() || brokers[msg.sender], "SND");
        require(maxAmounts.length > 0, "MTY"); // argument array is eMpTY
        ILiquidityManager(manager).callGenericModule(
            LibUtils.toBytes32("transferFromPoolByDex"),
            abi.encode(dexId, maxAmounts)
        );
        bytes memory result = ILiquidityManager(manager).callDexModule(
            dexId,
            LibUtils.toBytes32("addLiquidity"),
            abi.encode(maxAmounts, deadline, validationData)
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
        bytes memory result = ILiquidityManager(manager).callDexModule(
            dexId,
            LibUtils.toBytes32("removeLiquidity"),
            abi.encode(shareAmount, minAmounts, deadline)
        );
        (removedAmounts) = abi.decode(result, (uint256[]));
        ILiquidityManager(manager).callGenericModule(
            LibUtils.toBytes32("transferToPoolByDex"),
            abi.encode(dexId, removedAmounts)
        );
    }
}
