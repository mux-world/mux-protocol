// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SafeOwnable is OwnableUpgradeable {
    address private _pendingOwner;

    event OwnershipTransferring(address indexed pendingOwner);

    function __SafeOwnable_init() internal initializer {
        __Ownable_init();
    }

    function transferOwnership(address newOwner) public virtual override onlyOwner {
        require(newOwner != address(0), "ZeroNewOwner");
        require(newOwner != owner(), "SelfTransfer");
        _pendingOwner = newOwner;
        emit OwnershipTransferring(_pendingOwner);
    }

    function takeOwnership() public virtual {
        require(_msgSender() == _pendingOwner, "NowPendingOwner");
        _transferOwnership(_pendingOwner);
        _pendingOwner = address(0);
    }

    function renounceOwnership() public virtual override onlyOwner {
        _pendingOwner = address(0);
        _transferOwnership(address(0));
    }
}
