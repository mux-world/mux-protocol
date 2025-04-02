// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "../components/SafeOwnableUpgradeable.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IWETH9.sol";
import "../interfaces/INativeUnwrapper.sol";
import "../libraries/LibOrder.sol";

contract Storage is Initializable, SafeOwnableUpgradeable {
    bool private _reserved1; // this variable shares the same slot as SafeOwnableUpgradeable._pendingOwner
    OrderBookStorage internal _storage;
    bytes32[36] _gap;

    modifier whenPositionOrderEnabled() {
        require(!_storage.isPositionOrderPaused, "POP"); // Position Order Paused
        _;
    }

    modifier whenLiquidityOrderEnabled() {
        require(!_storage.isLiquidityOrderPaused, "LOP"); // Liquidity Order Paused
        _;
    }

    function brokers(address broker) external view returns (bool) {
        return _storage.brokers[broker];
    }

    function nextOrderId() external view returns (uint64) {
        return _storage.nextOrderId;
    }

    // 1e0
    function liquidityLockPeriod() external view returns (uint32) {
        return _storage.liquidityLockPeriod;
    }

    function rebalancers(address rebalancer) external view returns (bool) {
        return _storage.rebalancers[rebalancer];
    }

    function isPositionOrderPaused() external view returns (bool) {
        return _storage.isPositionOrderPaused;
    }

    function isLiquidityOrderPaused() external view returns (bool) {
        return _storage.isLiquidityOrderPaused;
    }

    function marketOrderTimeout() external view returns (uint32) {
        return _storage.marketOrderTimeout;
    }

    function maxLimitOrderTimeout() external view returns (uint32) {
        return _storage.maxLimitOrderTimeout;
    }

    function maintainer() external view returns (address) {
        return _storage.maintainer;
    }

    function referralManager() external view returns (address) {
        return _storage.referralManager;
    }

    function positionOrderExtras(uint64 orderId) external view returns (PositionOrderExtra memory) {
        return _storage.positionOrderExtras[orderId];
    }

    function cancelCoolDown() external view returns (uint32) {
        return _storage.cancelCoolDown;
    }
}
