// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "../orderbook/Types.sol";

library LibOrder {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    uint8 constant POSITION_INCREASING = 0x80; // 1 for openPosition, 0 for closePosition
    uint8 constant POSITION_MARKET_ORDER = 0x40; // ignore limitPrice
    uint8 constant POSITION_WITHDRAW_ALL_IF_EMPTY = 0x20; // auto withdraw all if position.size == 0

    bytes32 constant ORDER_TYPE_MASK = bytes32(uint256(0xff));

    struct OrderList {
        EnumerableSetUpgradeable.Bytes32Set _keys;
        mapping(bytes32 => bytes32[3]) _values;
    }

    function add(
        OrderList storage list,
        uint64 id,
        bytes32[3] memory value
    ) internal returns (bool) {
        list._values[bytes32(uint256(id))] = value;
        return list._keys.add(bytes32(uint256(id)));
    }

    function remove(OrderList storage list, uint64 id) internal returns (bool) {
        delete list._values[bytes32(uint256(id))];
        return list._keys.remove(bytes32(uint256(id)));
    }

    function contains(OrderList storage list, uint64 id) internal view returns (bool) {
        return list._keys.contains(bytes32(uint256(id)));
    }

    function length(OrderList storage list) internal view returns (uint256) {
        return list._keys.length();
    }

    function at(OrderList storage list, uint256 index) internal view returns (bytes32[3] memory) {
        return list._values[list._keys.at(index)];
    }

    function get(OrderList storage list, uint64 id) internal view returns (bytes32[3] memory value) {
        value = list._values[bytes32(uint256(id))];
    }

    function getOrderType(bytes32[3] memory orderData) internal pure returns (OrderType) {
        return OrderType(uint8(uint256(orderData[0])));
    }

    function getOrderOwner(bytes32[3] memory orderData) internal pure returns (address) {
        return address(bytes20(orderData[0]));
    }

    // TODO: use flags
    function encodePositionOrder(
        uint64 orderId,
        bytes32 subAccountId,
        uint96 collateral,
        uint96 size,
        uint96 price,
        uint8 profitTokenId,
        uint8 flags
    ) internal pure returns (bytes32[3] memory data) {
        require(subAccountId & ORDER_TYPE_MASK == 0, "InvalidSubAccountId");
        data[0] = subAccountId | bytes32(uint256(orderId) << 8) | bytes32(uint256(OrderType.PositionOrder));
        data[1] = bytes32((uint256(collateral) << 160) | (uint256(size) << 64) | (uint256(flags) << 56));
        data[2] = bytes32((uint256(price) << 160) | (uint256(profitTokenId) << 152));
    }

    function decodePositionOrder(bytes32[3] memory data) internal pure returns (PositionOrder memory order) {
        order.subAccountId = bytes32(bytes23(data[0]));
        order.collateral = uint96(bytes12(data[1]));
        order.size = uint96(bytes12(data[1] << 96));
        order.flags = uint8(bytes1(data[1] << 192));
        order.price = uint96(bytes12(data[2]));
        order.profitTokenId = uint8(bytes1(data[2] << 96));
    }

    function encodeLiquidityOrder(
        uint64 orderId,
        address account,
        uint8 assetId,
        uint96 amount,
        bool isAdding
    ) internal pure returns (bytes32[3] memory data) {
        uint8 flags = isAdding ? 1 : 0;
        data[0] = bytes32(
            (uint256(uint160(account)) << 96) | (uint256(orderId) << 8) | uint256(OrderType.LiquidityOrder)
        );
        data[1] = bytes32((uint256(amount) << 160) | (uint256(assetId) << 152) | (uint256(flags) << 144));
    }

    function decodeLiquidityOrder(bytes32[3] memory data) internal pure returns (LiquidityOrder memory order) {
        order.account = address(bytes20(data[0]));
        order.amount = uint96(bytes12(data[1]));
        order.assetId = uint8(bytes1(data[1] << 96));
        order.isAdding = uint8(bytes1(data[1] << 104)) > 0;
    }

    function encodeWithdrawalOrder(
        uint64 orderId,
        bytes32 subAccountId,
        uint96 amount,
        uint8 profitTokenId,
        bool isProfit
    ) internal pure returns (bytes32[3] memory data) {
        data[0] = subAccountId | bytes32(uint256(orderId) << 8) | bytes32(uint256(OrderType.WithdrawalOrder));
        data[1] = bytes32(
            (uint256(amount) << 160) | (uint256(profitTokenId) << 152) | (uint256(isProfit ? 1 : 0) << 144)
        );
    }

    function decodeWithdrawalOrder(bytes32[3] memory data) internal pure returns (WithdrawalOrder memory order) {
        order.subAccountId = bytes32(bytes23(data[0]));
        order.amount = uint96(bytes12(data[1]));
        order.profitTokenId = uint8(bytes1(data[1] << 96));
        order.isProfit = uint8(bytes1(data[1])) > 0;
    }

    function isIncreasing(PositionOrder memory order) internal pure returns (bool) {
        return (order.flags & POSITION_INCREASING) != 0;
    }

    function isMarketOrder(PositionOrder memory order) internal pure returns (bool) {
        return (order.flags & POSITION_MARKET_ORDER) != 0;
    }

    function isWithdrawIfEmpty(PositionOrder memory order) internal pure returns (bool) {
        return (order.flags & POSITION_WITHDRAW_ALL_IF_EMPTY) != 0;
    }
}
