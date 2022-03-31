// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../liquidity/Types.sol";

interface ILiquidityManager {
    function getAllDexSpotConfiguration() external view returns (DexSpotConfiguration[] memory);

    function getDexLiquidity(uint8 dexId) external returns (uint256[] memory liquidities, uint256 lpBalance);

    function getModuleInfo(bytes32 moduleId) external view returns (ModuleInfo memory);

    function moduleCall(CallContext memory context) external returns (bytes memory);

    function batchModuleCall(CallContext[] memory contexts) external returns (bytes[] memory results);
}
