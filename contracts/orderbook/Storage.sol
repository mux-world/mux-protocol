// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../components/SafeOwnableUpgradeable.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IWETH9.sol";
import "../interfaces/INativeUnwrapper.sol";
import "../libraries/LibOrder.sol";

contract Storage is Initializable, SafeOwnableUpgradeable {
    bool private _reserved1;
    mapping(address => bool) public brokers;
    ILiquidityPool internal _pool;
    uint64 internal _nextOrderId;
    LibOrder.OrderList internal _orders;
    IERC20Upgradeable internal _mlp;
    IWETH internal _weth;
    uint32 public liquidityLockPeriod; // 1e0
    INativeUnwrapper public _nativeUnwrapper;
    bytes32[50] _gap;
}
