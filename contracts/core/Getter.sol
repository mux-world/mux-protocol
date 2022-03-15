// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../libraries/LibSubAccount.sol";
import "./Storage.sol";

contract Getter is Storage {
    using LibSubAccount for bytes32;

    function getAssetInfo(uint8 assetId) public view returns (Asset memory) {
        return _storage.assets[assetId];
    }

    function getAllAssetInfo() public view returns (Asset[] memory) {
        return _storage.assets;
    }

    function getAssetAddress(uint8 assetId) public view returns (address) {
        return _storage.assets[assetId].tokenAddress;
    }

    function getShortFundingInfo()
        public
        view
        returns (
            uint32 baseRate8H,
            uint32 limitRate8H,
            uint128 cumulativeFunding,
            uint32 lastFundingTime
        )
    {
        baseRate8H = _storage.shortFundingConfiguration.baseRate8H;
        limitRate8H = _storage.shortFundingConfiguration.limitRate8H;
        cumulativeFunding = _storage.shortFunding.cumulativeFunding;
        lastFundingTime = _storage.shortFunding.lastFundingTime;
    }

    function getSubAccount(bytes32 subAccountId)
        public
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

    function getLiquidityLockInfo(address lp) public view returns (uint32 liquidityLockPeriod, uint32 liquidityLock) {
        liquidityLockPeriod = _storage.liquidityLockPeriod;
        liquidityLock = _storage.liquidityLocks[lp];
    }
}
