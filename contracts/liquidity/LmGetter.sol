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
        if (_dexSpotConfigs.length >= dexId) {
            if (_hasConnector(dexId)) {
                lpBalance = _getLpBalance(dexId);
                liquidities = _getDexRedeemableAmounts(dexId, lpBalance);
            } else {
                lpBalance = 0;
                liquidities = new uint256[](_dexSpotConfigs[dexId].assetIds.length);
            }
        }
    }

    function getDexRewards(uint8 dexId)
        external
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        return _getDexRewards(dexId);
    }

    function getDexFees(uint8 dexId) external returns (uint256[] memory rewardAmounts) {
        return _getDexFees(dexId);
    }

    function getDexRedeemableAmounts(uint8 dexId, uint256 shareAmount) external returns (uint256[] memory amounts) {
        return _getDexRedeemableAmounts(dexId, shareAmount);
    }
}
