// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./Types.sol";
import "./LmStorage.sol";
import "./LmDexProxy.sol";

contract LmGetter is LmStorage, LmDexProxy {
    function hasConnector(uint8 dexId) public view returns (bool) {
        return _hasConnector(dexId);
    }

    function getAllDexSpotConfiguration() public view returns (DexSpotConfiguration[] memory) {
        return _dexSpotConfigs;
    }

    function getDexConnector(uint8 dexId) public view returns (DexConnectorConfiguration memory) {
        return _dexConnectorConfigs[dexId];
    }

    function getDexLiquidity(uint8 dexId) public returns (uint256[] memory liquidities, uint256 lpBalance) {
        if (_hasConnector(dexId)) {
            lpBalance = _getLpBalance(dexId);
            liquidities = _getDexRedeemableAmounts(dexId, lpBalance);
        }
    }
}
