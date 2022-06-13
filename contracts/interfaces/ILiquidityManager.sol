// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../liquidity/Types.sol";

interface ILiquidityManager {
    function hasGenericCall(bytes32 methodId) external view returns (bool);

    function hasDexCall(uint8 dexId, bytes32 methodId) external view returns (bool);

    function getDexSpotConfiguration(uint8 dexId) external returns (DexSpotConfiguration memory);

    function getAllDexSpotConfiguration() external returns (DexSpotConfiguration[] memory);

    function getDexLiquidity(uint8 dexId) external returns (uint256[] memory liquidities, uint256 lpBalance);

    function getModuleInfo(bytes32 moduleId) external view returns (ModuleInfo memory);

    function callGenericModule(bytes32 methodId, bytes memory params) external returns (bytes memory);

    function callDexModule(
        uint8 dexId,
        bytes32 methodId,
        bytes memory params
    ) external returns (bytes memory);
}
