// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../liquidity/plugins/Plugin.sol";

contract TestPlugin is Plugin {
    function name() public pure override returns (string memory) {
        return "TestPlugin";
    }

    function exports() external pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = this.transfer.selector;
        selectors[1] = this.pullAssets.selector;
        selectors[2] = this.pushAssets.selector;
    }

    function transfer(
        address recipient,
        uint8[] memory assetIds,
        uint256[] memory amounts
    ) external {
        _fetchAssets(assetIds, amounts);
        for (uint256 i = 0; i < assetIds.length; i++) {
            IERC20(_getTokenAddress(assetIds[i])).transfer(recipient, amounts[i]);
        }
    }

    function pullAssets(uint8[] memory assetIds, uint256[] memory amounts) external {
        _fetchAssets(assetIds, amounts);
    }

    function pushAssets(uint8[] memory assetIds, uint256[] memory amounts) external {
        _pushAssets(assetIds, amounts);
    }
}
