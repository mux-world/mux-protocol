// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../components/SafeOwnableUpgradeable.sol";
import "../libraries/LibSubAccount.sol";
import "./Types.sol";
import "./Events.sol";

contract Storage is Initializable, SafeOwnableUpgradeable, Events {
    uint32 internal constant FUNDING_PERIOD = 3600 * 8;

    LiquidityPoolStorage internal _storage;

    modifier onlyOrderBook() {
        require(_msgSender() == _storage.orderBook, "BOK"); // can only be called by order BOoK
        _;
    }

    modifier onlyLiquidityManager() {
        require(_msgSender() == _storage.liquidityManager, "LQM"); // can only be called by LiQuidity Manager
        _;
    }

    modifier updateSequence() {
        _;
        unchecked {
            _storage.sequence += 1;
        }
        emit UpdateSequence(_storage.sequence);
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    function _hasAsset(uint8 assetId) internal view returns (bool) {
        return assetId < _storage.assets.length;
    }

    function _isStable(uint8 tokenId) internal view returns (bool) {
        return _storage.assets[tokenId].isStable;
    }

    bytes32[50] internal _gap;
}
