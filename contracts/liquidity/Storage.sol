// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IConnector.sol";
import "../components/SafeOwnableUpgradeable.sol";
import "./Types.sol";

contract CrossStorage {
    address internal _vault;
    address internal _pool;
    DexSpotConfiguration[] internal _dexSpotConfigs;
    mapping(bytes32 => bytes32[]) internal _moduleData;
    bytes32[50] private __moduleGaps;
}

contract Storage is CrossStorage {
    mapping(bytes32 => ModuleInfo) internal _moduleInfos;
    mapping(bytes32 => CallRegistration) internal _genericRoutes; // method -> call
    mapping(uint8 => mapping(bytes32 => CallRegistration)) internal _dexRoutes; // dexId -> method -> call
    mapping(address => bool) internal _externalAccessors;
    bytes32[50] private __gaps;
}
