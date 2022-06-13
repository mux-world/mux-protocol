// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../libraries/LibOrder.sol";

contract TestLibOrder {
    using LibOrder for LibOrder.OrderList;

    LibOrder.OrderList internal _orders;

    function add(uint64 orderId) external {
        bytes32[3] memory order;
        order[0] = bytes32(uint256(orderId));
        _orders.add(orderId, order);
    }

    function remove(uint64 orderId) external {
        _orders.remove(orderId);
    }

    function contains(uint64 orderId) external view returns (bool) {
        return _orders.contains(orderId);
    }

    function length() external view returns (uint256) {
        return _orders.length();
    }

    function at(uint256 index) external view returns (uint256) {
        bytes32[3] memory order = _orders.at(index);
        return uint256(order[0]);
    }

    function get(uint64 orderId) external view returns (uint256) {
        bytes32[3] memory order = _orders.get(orderId);
        return uint256(order[0]);
    }
}
