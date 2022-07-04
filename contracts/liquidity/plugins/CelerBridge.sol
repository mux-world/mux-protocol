// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Plugin.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract CelerBridge is Plugin {
    using Address for address;

    event BridgePeerTransfer(
        address indexed bridge,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint64 dstChainId,
        bytes extraData
    );
    event SetTransferPermission(uint256 chainId, uint8 assetId, bool isAllowed);

    function name() public pure override returns (string memory) {
        return "CelerBridge";
    }

    function exports() public pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = this.celerTransfer.selector;
        selectors[1] = this.getCelerBridgePermission.selector;
        selectors[2] = this.setCelerBridgePermission.selector;
    }

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
        }
    }

    function getCelerBridgePermission(uint256 chainId, uint8 assetId) public view returns (bool isAllowed) {
        isAllowed = _getStateAsUint256(_permissionKey(chainId, assetId)) > 0;
    }

    function setCelerBridgePermission(
        uint256 chainId,
        uint8 assetId,
        bool isAllowed
    ) public onlyOwner {
        _setStateAsUint256(_permissionKey(chainId, assetId), isAllowed ? 1 : 0);
        emit SetTransferPermission(chainId, assetId, isAllowed);
    }

    function _permissionKey(uint256 chainId, uint8 assetId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(chainId, assetId));
    }

    function celerTransfer(
        uint8 assetId,
        uint256 amount,
        uint256 dstChainId,
        uint256 maxSlippage
    ) public onlyOwner {
        require(getCelerBridgePermission(dstChainId, assetId), "CelerBridge::NotPermitted");
        require(amount != 0, "CelerBridge::ZeroAmount");
        require(dstChainId <= type(uint64).max, "CelerBridge::ChainIdOutOfRange");
        require(maxSlippage <= type(uint32).max, "CelerBridge::SlippageOutOfRange");

        address token = _tryGetTokenAddress(assetId);
        require(token != address(0), "CelerBridge::InvalidTokenAddress");

        address recipient = getPeers(dstChainId);
        require(recipient != address(0), "CelerBridge::NoPeer");

        address bridge = getBridge();
        require(bridge != address(0), "CelerBridge::NoBridge");

        uint8[] memory assetIds = new uint8[](1);
        uint256[] memory amounts = new uint256[](1);
        assetIds[0] = assetId;
        amounts[0] = amount;
        _fetchAssets(assetIds, amounts);

        try IERC20(token).approve(bridge, amount) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("CelerBridge::FailtoCallApprove");
        }
        uint64 nonce = uint64(block.timestamp);
        try
            ICelerBridge(bridge).send(recipient, token, amount, uint64(dstChainId), nonce, uint32(maxSlippage))
        {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("CelerBridge::FailtoCallBridgeSend");
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
