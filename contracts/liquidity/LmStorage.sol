// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IConnector.sol";
import "../components/SafeOwnable.sol";
import "./Types.sol";

contract LmStorage is Initializable, SafeOwnable {
    ILiquidityPool internal _pool;
    DexSpotConfiguration[] internal _dexSpotConfigs;
    mapping(uint8 => DexConnectorConfiguration) internal _dexConnectorConfigs;
    mapping(uint8 => address) internal _tokenCache;

    bytes32[50] __gaps;
}
