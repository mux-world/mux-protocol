// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

interface IOrderBook {
    function liquidityLockPeriod() external view returns (uint32);

    function getOrder(uint64 orderId) external view returns (bytes32[3] memory, bool);
}
