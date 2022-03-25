// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../components/SafeOwnable.sol";

contract Admin is SafeOwnable {
    bool public isPaused;
    mapping(address => bool) public brokers;

    event AddBroker(address indexed newBroker);
    event RemoveBroker(address indexed newBroker);

    modifier onlyBroker() {
        require(brokers[_msgSender()], "Bkr");
        _;
    }

    modifier onlyNotPaused() {
        require(!isPaused, "Psd");
        _;
    }

    function addBroker(address newBroker) public onlyOwner {
        require(!brokers[newBroker], "Bkr");
        brokers[newBroker] = true;
        emit AddBroker(newBroker);
    }

    function removeBroker(address broker) public onlyOwner {
        _removeBroker(broker);
    }

    function renounceBroker() public {
        _removeBroker(msg.sender);
    }

    function _removeBroker(address broker) internal {
        require(brokers[broker], "Bkr");
        brokers[broker] = false;
        emit RemoveBroker(broker);
    }
}
