// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/ILiquidityManager.sol";
import "../../libraries/LibUtils.sol";
import "../Types.sol";

contract DexLiquidityLens {
    function getDexLiquidity(address liquidityManager, uint8 dexId)
        external
        returns (uint256[] memory liquidities, uint256 lpBalance)
    {
        bytes memory lpBalanceRaw = ILiquidityManager(liquidityManager).moduleCall(
            CallContext({ dexId: dexId, methodId: LibUtils.toBytes32("getLpBalance"), params: "" })
        );
        bytes memory liquiditiesRaw = ILiquidityManager(liquidityManager).moduleCall(
            CallContext({ dexId: dexId, methodId: LibUtils.toBytes32("getSpotAmounts"), params: lpBalanceRaw })
        );
        lpBalance = abi.decode(lpBalanceRaw, (uint256));
        liquidities = abi.decode(liquiditiesRaw, (uint256[]));
    }
}
