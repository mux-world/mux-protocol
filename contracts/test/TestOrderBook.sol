// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../orderbook/OrderBook.sol";

contract TestOrderBook is OrderBook {
    uint32 _ts;

    function setBlockTimestamp(uint32 ts) external {
        _ts = ts;
    }

    function _blockTimestamp() internal view override returns (uint32) {
        return _ts;
    }
}
