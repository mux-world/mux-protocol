// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../components/SafeOwnable.sol";
import "../libraries/LibSubAccount.sol";
import "./Types.sol";
import "./Events.sol";

contract Storage is Initializable, SafeOwnable, Events {
    uint32 internal constant FUNDING_PERIOD = 3600 * 8;

    LiquidityPoolStorage internal _storage;

    modifier onlyOrderBook() {
        require(_msgSender() == _storage.orderBook, "Bok"); // can only be called by order BOoK
        _;
    }

    modifier onlyLiquidityManager() {
        require(_msgSender() == _storage.liquidityManager, "LqM"); // can only be called by LiQuidity Manager
        _;
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
