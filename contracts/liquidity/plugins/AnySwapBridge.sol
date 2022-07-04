// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Plugin.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract AnySwapBridge is Plugin {
    using Address for address;

    event BridgePeerTransfer(
        address indexed bridge,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint64 dstChainId,
        bytes extraData
    );

    function name() public pure override returns (string memory) {
        return "AnySwapBridge";
    }

    function exports() public pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = this.anySwapTransfer.selector;
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
            }
            case 250 {
                // fantom
                bridge := 0xE3e0C14bbCBF86b3Ff60E8666C070d34b84F3f73
            }
            case 42161 {
                // arbitrum
                bridge := 0xc931f61b1534eb21d8c11b24f3f5ab2471d4ab50
            }
            case 56 {
                // bsc
                bridge := 0xb0731d50c681c45856bfc3f7539d5f61d4be81d8
            }
        }
    }

    function anySwapTransfer(
        uint8 assetId,
        uint256 amount,
        uint256 dstChainId,
        uint256 maxSlippage
    ) public {
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
