// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./Storage.sol";

contract Admin is Storage {
    event AddBroker(address indexed newBroker);
    event RemoveBroker(address indexed newBroker);
    event SetLiquidityLockPeriod(uint32 oldLockPeriod, uint32 newLockPeriod);

    modifier onlyBroker() {
        require(brokers[_msgSender()], "BKR"); // only BroKeR
        _;
    }

    function addBroker(address newBroker) external onlyOwner {
        require(!brokers[newBroker], "BKR"); // BroKeR existed
        brokers[newBroker] = true;
        emit AddBroker(newBroker);
    }

    function removeBroker(address broker) external onlyOwner {
        _removeBroker(broker);
    }

    function renounceBroker() external {
        _removeBroker(msg.sender);
    }

    function setLiquidityLockPeriod(uint32 newLiquidityLockPeriod) external onlyOwner {
        require(newLiquidityLockPeriod <= 86400 * 30, "LCK"); // LoCK time is too large
        require(liquidityLockPeriod != newLiquidityLockPeriod, "CHG"); // setting is not CHanGed
        emit SetLiquidityLockPeriod(liquidityLockPeriod, newLiquidityLockPeriod);
        liquidityLockPeriod = newLiquidityLockPeriod;
    }

    function _removeBroker(address broker) internal {
        require(brokers[broker], "BKR"); // BroKeR not found
        brokers[broker] = false;
        emit RemoveBroker(broker);
    }
}
