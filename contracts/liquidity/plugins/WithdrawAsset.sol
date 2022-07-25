// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Plugin.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract WithdrawAsset is Plugin {
    function name() public pure override returns (string memory) {
        return "WithdrawAsset";
    }

    function getChainId() public view returns (uint256) {
        return block.chainid;
    }

    function exports() public pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = this.withdrawAsset2.selector;
        selectors[1] = this.withdrawAsset3.selector;
    }

    function withdrawAsset2(uint8[] memory assetIds, uint256[] memory amounts) public onlyOwner {
        _fetchAssets(assetIds, amounts);
        _transferTo(msg.sender, assetIds, amounts);
    }

    function withdrawAsset3(
        uint8[] memory assetIds,
        uint256[] memory amounts,
        address recipient
    ) public onlyOwner {
        _fetchAssets(assetIds, amounts);
        _transferTo(recipient, assetIds, amounts);
    }
}
