// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../liquidity/Types.sol";

interface ILiquidityManager {
    function getDexSpotConfiguration(uint8 dexId) external returns (DexSpotConfiguration memory);

    function getAllDexSpotConfiguration() external returns (DexSpotConfiguration[] memory);

    function getDexLiquidity(uint8 dexId) external returns (uint256[] memory liquidities, uint256 lpBalance);

    function getDexAdapterConfig(uint8 dexId) external view returns (bytes memory config);

    function getDexAdapterState(uint8 dexId, bytes32 key) external view returns (bytes32 state);

    function getDexAdapter(uint8 dexId) external view returns (DexRegistration memory registration);
}
