// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../libraries/LibSubAccount.sol";
import "./Storage.sol";

contract Getter is Storage {
    using LibSubAccount for bytes32;

    function getAssetInfo(uint8 assetId) external view returns (Asset memory) {
        require(assetId < _storage.assets.length, "Lst"); // the asset is not LiSTed
        return _storage.assets[assetId];
    }

    function getAllAssetInfo() external view returns (Asset[] memory) {
        return _storage.assets;
    }

    function getAssetAddress(uint8 assetId) external view returns (address) {
        require(assetId < _storage.assets.length, "Lst"); // the asset is not LiSTed
        return _storage.assets[assetId].tokenAddress;
    }

    function getLiquidityPoolStorage()
        external
        view
        returns (
            // [0] shortCumulativeFunding
            uint128[1] memory u128s,
            // [0] shortFundingBaseRate8H
            // [1] shortFundingLimitRate8H
            // [2] lastFundingTime
            // [3] fundingInterval
            // [4] liquidityLockPeriod
            uint32[5] memory u32s
        )
    {
        u32s[0] = _storage.shortFundingBaseRate8H;
        u32s[1] = _storage.shortFundingLimitRate8H;
        u128s[0] = _storage.shortCumulativeFunding;
        u32s[2] = _storage.lastFundingTime;
        u32s[3] = _storage.fundingInterval;
        u32s[4] = _storage.liquidityLockPeriod;
    }

    function getSubAccount(bytes32 subAccountId)
        external
        view
        returns (
            uint96 collateral,
            uint96 size,
            uint32 lastIncreasedTime,
            uint96 entryPrice,
            uint128 entryFunding
        )
    {
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        collateral = subAccount.collateral;
        size = subAccount.size;
        lastIncreasedTime = subAccount.lastIncreasedTime;
        entryPrice = subAccount.entryPrice;
        entryFunding = subAccount.entryFunding;
    }

    function getLiquidityLockInfo(address lp)
        external
        view
        returns (
            uint32 liquidityLockPeriod,
            uint32 lastAddedTime,
            uint96 pendingMLP
        )
    {
        liquidityLockPeriod = _storage.liquidityLockPeriod;
        LiquidityLock storage lock = _storage.liquidityLocks[lp];
        lastAddedTime = lock.lastAddedTime;
        pendingMLP = lock.pendingMLP;
    }
}
