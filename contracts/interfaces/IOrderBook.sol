// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IOrderBook {
    function liquidityLockPeriod() external view returns (uint32);
}
