// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../core/LiquidityPool.sol";

contract TestLiquidityPool is LiquidityPool {
    uint32 _ts;

    function setBlockTimestamp(uint32 ts_) external {
        _ts = ts_;
    }

    function _blockTimestamp() internal view override returns (uint32) {
        return _ts;
    }
}
