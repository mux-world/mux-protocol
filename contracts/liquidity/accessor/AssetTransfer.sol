// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../../interfaces/ILiquidityManager.sol";
import "../../libraries/LibUtils.sol";

import "../../components/SafeOwnable.sol";

/**
 * @title AssetTransfer is a wrapper of liquidity managing methods for `LiquidityManager`.
 *        It has limited privileges.
 */
contract AssetTransfer is SafeOwnable {
    using EnumerableSet for EnumerableSet.UintSet;

    address public manager;
    mapping(address => bool) public brokers;
    mapping(uint8 => mapping(uint256 => bytes32)) public tokenBridges;

    // mapping(uint256 => bytes32) public tokenBridgeModules;
    // EnumerableSet.UintSet internal _assetList;

    event SetBroker(address indexed broker, bool enable);
    event SetTokenBridge(uint8 asset, uint256 chainId, bytes32 moduleName);

    constructor(address liquidityManager_) SafeOwnable() {
        manager = liquidityManager_;
    }

    function setTokenBridge(
        uint8 asset,
        uint256 destChainId,
        bytes32 moduleName
    ) external {}

    /**
     * @notice Enable or disable an address as broker. Broker is able to call add / remove liquidity methods.
     */
    function setBroker(address broker, bool enable) external onlyOwner {
        require(brokers[broker] != enable, "BNC"); // broker status is not changed
        brokers[broker] = enable;
        emit SetBroker(broker, enable);
    }

    function transferToPeer(
        uint8 assetId,
        uint256 amount,
        uint256 destChainId,
        uint256 maxSlippage
    ) external {
        require(msg.sender == owner() || brokers[msg.sender], "SND"); // sender is not allowed
        bytes32 methodId = tokenBridges[assetId][destChainId];
        require(methodId != bytes32(0), "BMS"); // bridge not set
        ILiquidityManager(manager).callGenericModule(methodId, abi.encode(assetId, amount, destChainId, maxSlippage));
    }

    function receiveAssets(uint8[] memory assetIds, uint256[] memory amounts) external {
        require(msg.sender == owner() || brokers[msg.sender], "SND"); // sender is not allowed
        ILiquidityManager(manager).callGenericModule(
            LibUtils.toBytes32("transferToPool"),
            abi.encode(assetIds, amounts)
        );
    }
}
