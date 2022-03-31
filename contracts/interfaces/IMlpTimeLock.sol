// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IMlpTimeLock {
    function getLiquidityLockInfo(address lp)
        external
        view
        returns (
            uint32 liquidityLockPeriod,
            uint32 lastAddedTime,
            uint96 pendingMLP
        );

    function addMlp(
        address lp,
        uint96 mlpAmount // LiquidityPool SHOULD sent MlpToken to MlpTimeLock
    ) external;
}
