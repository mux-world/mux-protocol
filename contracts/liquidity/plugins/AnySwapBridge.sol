// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./TokenBridge.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract AnySwapBridge is TokenBridge {
    using Address for address;

    function name() public pure override returns (string memory) {
        return "AnySwapBridge";
    }

    function exports() public pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = this.anySwapTransfer.selector;
        selectors[1] = this.getAnySwapBridgePermission.selector;
        selectors[2] = this.setAnySwapBridgePermission.selector;
    }

    function getBridge() public view returns (address bridge) {
        assembly {
            switch chainid()
            case 42161 {
                // arbitrum
                bridge := 0x650Af55D5877F289837c30b94af91538a7504b76
            }
            case 43114 {
                // ava
                bridge := 0xb0731d50c681c45856bfc3f7539d5f61d4be81d8
            }
            case 56 {
                // bsc
                bridge := 0x171a9377C5013bb06Bca8CfE22B9C007f2C319F1
            }
            case 250 {
                // fantom
                bridge := 0xE3e0C14bbCBF86b3Ff60E8666C070d34b84F3f73
            }
        }
    }

    function getAnySwapBridgePermission(uint256 chainId, uint8 assetId) public view returns (bool isAllowed) {
        isAllowed = _getStateAsUint256(_permissionKey(chainId, assetId)) > 0;
    }

    function setAnySwapBridgePermission(
        uint256 chainId,
        uint8 assetId,
        bool isAllowed
    ) public onlyOwner {
        _setPermission(chainId, assetId, isAllowed);
    }

    function anySwapTransfer(
        uint8 assetId,
        uint256 amount,
        uint256 dstChainId,
        uint256 maxSlippage
    ) public onlyMaintainer {
        require(amount != 0, "Amount is zero");
        require(dstChainId <= type(uint64).max, "ChainId is out of range");
        require(maxSlippage == 0, "Slippage is not supported");

        address token = _getTokenAddress(assetId);
        require(token != address(0), "Invalid token");

        address recipient = getPeers(dstChainId);
        require(recipient != address(0), "No recipient in target network");

        address bridge = getBridge();
        require(bridge != address(0), "Bridge not exists in current network");
        // require(bridge.isContract(), "Bridge is not a contract");

        try IERC20(token).approve(bridge, amount) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("Fail to call bridge send");
        }
        try IAnySwapBridge(bridge).anySwapOutUnderlying(token, recipient, amount, dstChainId) {} catch Error(
            string memory reason
        ) {
            revert(reason);
        } catch {
            revert("Fail to call bridge send");
        }

        emit BridgePeerTransfer(bridge, recipient, token, amount, uint64(dstChainId), "");
    }
}

interface IAnySwapBridge {
    function anySwapOutUnderlying(
        address token,
        address to,
        uint256 amount,
        uint256 toChainID
    ) external;
}
