// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./Storage.sol";
import "./Trade.sol";
import "./Getter.sol";
import "./Admin.sol";

contract LiquidityPool is Storage, Trade, Admin, Getter {
    function initialize(address mlp) external initializer {
        __SafeOwnable_init();

        _storage.mlp = mlp;
    }
}
