// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../liquidity/LiquidityManager.sol";

contract TestLiquidityManager is LiquidityManager {
    function getContextDexId() public view returns (uint8) {
        return _dexContext.dexId;
    }

    function getDexLpBalanceNested(uint8 dexId0, uint8 dexId1) public dexCall(dexId0) {
        DexRegistration storage registration = _dexAdapters[dexId0];
        if (_dexAdapters[dexId0].adapter != address(0)) {
            _delegateCall(registration.adapter, abi.encodeWithSelector(IDexAdapter.getLpBalance.selector));
        }
        getDexLpBalance(dexId1);
    }

    function testContextDexId(uint8[] memory dexIdSequence) external {
        for (uint256 i = 0; i < dexIdSequence.length; i++) {
            require(getContextDexId() == 0, "!ID0");
            getDexLpBalance(dexIdSequence[i]);
            require(getContextDexId() == 0, "!ID1");
        }
        require(getContextDexId() == 0, "!ID1");
    }
}
