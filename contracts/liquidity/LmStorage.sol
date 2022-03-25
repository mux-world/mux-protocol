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
    mapping(uint8 => bytes) internal _dexContexts;
    mapping(uint8 => address) internal _tokenCache;
    mapping(uint256 => BridgeConfiguration) internal _bridgeConfigs;
    address internal _vault;

    function _getAssetAddress(uint8 assetId) internal returns (address) {
        if (_tokenCache[assetId] == address(0)) {
            address assetAddress = _pool.getAssetAddress(assetId);
            _tokenCache[assetId] = assetAddress;
            return assetAddress;
        }
        return _tokenCache[assetId];
    }

    bytes32[50] __gaps;
}
