// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Plugin.sol";

abstract contract TokenBridge is Plugin {
    event BridgePeerTransfer(
        address indexed bridge,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint64 dstChainId,
        bytes extraData
    );
    event SetTransferPermission(uint256 chainId, uint8 assetId, bool isAllowed);

    function getPeers(uint256 chainId) public pure returns (address peer) {
        assembly {
            switch chainId
            case 42161 {
                // arbitrum
                peer := 0x02FAe054ACD7FB1615471319c4E3029DFbC2B23C
            }
            case 43114 {
                // ava
                peer := 0x28f16eB86481066Bf63BcBEB05C8474f7120A36C
            }
            case 56 {
                // bsc
                peer := 0xee85CDdCe0CF068091081eA0fcd53f279aa3B09F
            }
            case 250 {
                // fantom
                peer := 0x5898c3E218a8501533d771C86e2fA37743ea2aDd
            }
            case 10 {
                // optimism
                peer := 0xFEc3704f4A02cB0EE6C7d52Cbf72b11E0441E9d5
            }
        }
    }

    function _setPermission(uint256 chainId, uint8 assetId, bool isAllowed) internal {
        _setStateAsUint256(_permissionKey(chainId, assetId), isAllowed ? 1 : 0);
        emit SetTransferPermission(chainId, assetId, isAllowed);
    }

    function _permissionKey(uint256 chainId, uint8 assetId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(chainId, assetId));
    }
}
