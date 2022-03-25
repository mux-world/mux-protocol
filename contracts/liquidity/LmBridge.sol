// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/ICBridge.sol";
import "./LmStorage.sol";
import "./Types.sol";

contract LmBridge is LmStorage {
    function _hasBridge(uint256 chainId) internal view returns (bool) {
        return _bridgeConfigs[chainId].chainId != 0;
    }

    function _bridgeTransfer(
        BridgeConfiguration storage bridgeConfig,
        address asset,
        uint256 amount
    ) internal {
        if (bridgeConfig.provider == BridgeProvider.Celer) {
            _celerBridgeTransfer(bridgeConfig, asset, amount);
        } else {
            revert("!!B");
        }
    }

    function _celerBridgeTransfer(
        BridgeConfiguration storage bridgeConfig,
        address asset,
        uint256 amount
    ) internal {
        uint32 slippage = abi.decode(bridgeConfig.extraData, (uint32));
        ICBridge(bridgeConfig.bridge).send(
            bridgeConfig.recipient,
            asset,
            amount,
            uint64(bridgeConfig.chainId),
            uint64(bridgeConfig.nonce++),
            slippage
        );
    }
}
