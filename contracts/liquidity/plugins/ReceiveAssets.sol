// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Plugin.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract ReceiveAssets is Plugin {
    function name() public pure override returns (string memory) {
        return "ReceiveAssets";
    }

    function exports() public pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = this.receiveAssets1.selector;
        selectors[1] = this.receiveAssets2.selector;
    }

    function receiveAssets1(uint8[] memory assetIds) public onlyOwner {
        uint256[] memory amounts = new uint256[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; i++) {
            address token = _tryGetTokenAddress(assetIds[i]);
            amounts[i] = IERC20(token).balanceOf(address(this));
        }
        _pushAssets(assetIds, amounts);
    }

    function receiveAssets2(uint8[] memory assetIds, uint256[] memory amounts) public onlyOwner {
        _pushAssets(assetIds, amounts);
    }
}
