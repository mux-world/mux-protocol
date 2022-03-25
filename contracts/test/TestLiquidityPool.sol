// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../core/LiquidityPoolHop1.sol";
import "../core/LiquidityPoolHop2.sol";

contract TestLiquidityPoolInject {
    // bytes32(uint256(keccak256('muxProtocol.test.liquidityPoolInject')) - 1))
    bytes32 internal constant INJECT_SLOT = 0xa9ab107d1860ddd07920004408d46a53e992574e5583bb794948b03e5e074bed;

    struct Injected {
        uint32 ts;
    }

    function getInjected() internal pure returns (Injected storage ds) {
        bytes32 slot = INJECT_SLOT;
        assembly {
            ds.slot := slot
        }
    }
}

contract TestLiquidityPoolHop1 is LiquidityPoolHop1, TestLiquidityPoolInject {
    function setBlockTimestamp(uint32 ts) external {
        TestLiquidityPoolInject.Injected storage injected = getInjected();
        injected.ts = ts;
    }

    function _blockTimestamp() internal view override returns (uint32) {
        TestLiquidityPoolInject.Injected storage injected = getInjected();
        return injected.ts;
    }
}

contract TestLiquidityPoolHop2 is LiquidityPoolHop2, TestLiquidityPoolInject {
    function _blockTimestamp() internal view override returns (uint32) {
        TestLiquidityPoolInject.Injected storage injected = getInjected();
        return injected.ts;
    }

    function getFundingRatePublic(
        uint32 baseRate8H, // 1e5
        uint32 limitRate8H, // 1e5
        uint32 utilization, // 1e5
        uint32 timespan // 1e0
    ) external pure returns (uint32 newFundingRate, uint128 cumulativeFunding) {
        return _getFundingRate(baseRate8H, limitRate8H, utilization, timespan);
    }
}

// only used for typechain
contract TestLiquidityPool is LiquidityPoolHop1, LiquidityPoolHop2 {
    function setBlockTimestamp(uint32 ts_) external {}

    function getFundingRatePublic(
        uint32 baseRate8H, // 1e5
        uint32 limitRate8H, // 1e5
        uint32 utilization, // 1e5
        uint32 timespan // 1e0
    ) external pure returns (uint32 newFundingRate, uint128 cumulativeFunding) {}
}
