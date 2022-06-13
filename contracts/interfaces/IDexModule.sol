// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./IModule.sol";

interface IDexModule is IModule {
    function tokens() external view returns (bool needCheck, address[] memory tokens_);
}
