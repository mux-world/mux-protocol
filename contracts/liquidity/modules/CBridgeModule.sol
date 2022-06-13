// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Module.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract CBridgeModule is Module {
    using Address for address;

    event BridgePeerTransfer(
        address indexed bridge,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint64 dstChainId,
        bytes extraData
    );

    function getPeers(uint256 chainId) public pure returns (address peer) {
        assembly {
            switch chainId
            case 43114 {
                // ava
                peer := 0x28f16eB86481066Bf63BcBEB05C8474f7120A36C
            }
            case 250 {
                // fantom
                peer := 0x5898c3E218a8501533d771C86e2fA37743ea2aDd
            }
            case 56 {
                // bsc
                peer := 0xee85CDdCe0CF068091081eA0fcd53f279aa3B09F
            }
            case 42161 {
                // arbitrum
                peer := 0x02FAe054ACD7FB1615471319c4E3029DFbC2B23C
            }
            case 97 {
                // testnet bsc
                peer := 0xe3124B1F5B7c793B6B4C97aFcAD7C6df6c1A9bc9
            }
            case 5 {
                // testnet goerli
                peer := 0xe3124B1F5B7c793B6B4C97aFcAD7C6df6c1A9bc9
            }
        }
    }

    function getBridge() public view returns (address bridge) {
        assembly {
            switch chainid()
            case 43114 {
                // ava
                bridge := 0xef3c714c9425a8F3697A9C969Dc1af30ba82e5d4
            }
            case 250 {
                // fantom
                bridge := 0x374B8a9f3eC5eB2D97ECA84Ea27aCa45aa1C57EF
            }
            case 56 {
                // bsc
                bridge := 0xdd90E5E87A2081Dcf0391920868eBc2FFB81a1aF
            }
            case 42161 {
                // arbitrum
                bridge := 0x1619DE6B6B20eD217a58d00f37B9d47C7663feca
            }
            case 97 {
                bridge := 0xf89354f314faf344abd754924438ba798e306df2
            }
            case 5 {
                bridge := 0x358234b325ef9ea8115291a8b81b7d33a2fa762d
            }
        }
    }

    function id() public pure override returns (bytes32) {
        return "cbridge-transfer-mod";
    }

    function meta()
        public
        pure
        override
        returns (
            bytes32[] memory ids,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        )
    {
        ids = new bytes32[](1);
        ids[0] = LibUtils.toBytes32("cBridgeTransferById");
        selectors = new bytes4[](1);
        selectors[0] = this.cBridgeTransferById.selector;
        initialStates = new bytes32[](0);
    }

    function cBridgeTransferById(
        uint8 assetId,
        uint256 amount,
        uint256 dstChainId,
        uint256 maxSlippage
    ) public {
        require(amount != 0, "Amount is zero");
        require(dstChainId <= type(uint64).max, "ChainId is out of range");
        require(maxSlippage <= type(uint32).max, "Slippage is out of range");

        address token = _getTokenAddr(assetId);
        require(token != address(0), "Invalid token");

        address recipient = getPeers(dstChainId);
        require(recipient != address(0), "No recipient in target network");

        address bridge = getBridge();
        require(bridge != address(0), "Bridge not exists in current network");
        // require(bridge.isContract(), "Bridge is not a contract");

        uint64 nonce = uint64(block.timestamp);
        try IERC20(token).approve(bridge, amount) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("Fail to call bridge send");
        }
        try
            ICelerBridge(bridge).send(recipient, token, amount, uint64(dstChainId), nonce, uint32(maxSlippage))
        {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("Fail to call bridge send");
        }
        emit BridgePeerTransfer(bridge, recipient, token, amount, uint64(dstChainId), abi.encode(nonce, maxSlippage));
    }
}

interface ICelerBridge {
    function send(
        address _receiver,
        address _token,
        uint256 _amount,
        uint64 _dstChainId,
        uint64 _nonce,
        uint32 _maxSlippage // slippage * 1M, eg. 0.5% -> 5000
    ) external;
}
