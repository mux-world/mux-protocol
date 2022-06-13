// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../liquidity/Types.sol";

interface ILiquidityManager {
    function hasGenericCall(bytes32 methodId) external view returns (bool);

    function hasDexCall(uint8 dexId, bytes32 methodId) external view returns (bool);

    function getDexSpotConfiguration(uint8 dexId) external view returns (DexSpotConfiguration memory);

    function getAllDexSpotConfiguration() external view returns (DexSpotConfiguration[] memory);

    function getDexLiquidity(uint8 dexId) external returns (uint256[] memory liquidities, uint256 lpBalance);

    function getModuleInfo(bytes32 moduleId) external view returns (ModuleInfo memory);

    function moduleCall(CallContext memory context) external returns (bytes memory);

    function batchModuleCall(CallContext[] memory contexts) external returns (bytes[] memory results);
}
