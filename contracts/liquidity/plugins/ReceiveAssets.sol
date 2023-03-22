// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Plugin.sol";

interface INativeWrapper {
    function deposit() external payable;
}

/**
 * @notice A patch to transfer received tokens to liquidity pool.
 */
contract ReceiveAssets is Plugin {
    function name() public pure override returns (string memory) {
        return "ReceiveAssets";
    }

    function getChainId() public view returns (uint256) {
        return block.chainid;
    }

    function getWrappedNative() public view returns (address wrapper, uint8 assetId) {
        assembly {
            switch chainid()
            case 42161 {
                // arbitrum
                wrapper := 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
                assetId := 3
            }
            case 43114 {
                // ava
                wrapper := 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7
                assetId := 5
            }
            case 56 {
                // bsc
                wrapper := 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c
                assetId := 6
            }
            case 250 {
                // fantom
                wrapper := 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83
                assetId := 7
            }
            case 10 {
                // optimism
                wrapper := 0x4200000000000000000000000000000000000006
                assetId := 3
            }
        }
    }

    function exports() public pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = this.receiveAssets1.selector;
        selectors[1] = this.receiveAssets2.selector;
        selectors[2] = this.receiveNative.selector;
    }

    function receiveNative() public {
        (address wrapper, uint8 assetId) = getWrappedNative();
        require(wrapper != address(0), "ReceiveAssets::InvalidWrapper");
        uint256 amount = address(this).balance;
        try INativeWrapper(wrapper).deposit{ value: amount }() {
            uint8[] memory assetIds = new uint8[](1);
            uint256[] memory amounts = new uint256[](1);
            assetIds[0] = assetId;
            amounts[0] = amount;
            _pushAssets(assetIds, amounts);
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("CelerBridge::FailtoCallApprove");
        }
    }

    function receiveAssets1(uint8[] memory assetIds) public {
        uint256[] memory amounts = new uint256[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; i++) {
            address token = _tryGetTokenAddress(assetIds[i]);
            amounts[i] = IERC20(token).balanceOf(address(this));
        }
        _pushAssets(assetIds, amounts);
    }

    function receiveAssets2(uint8[] memory assetIds, uint256[] memory amounts) public {
        _pushAssets(assetIds, amounts);
    }
}
