// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./LmStorage.sol";

contract LmTransfer is LmStorage {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function _transferFromLiquidityPool(uint8[] memory assetIds, uint256[] memory amounts) internal {
        require(assetIds.length == amounts.length, "Len"); // LENgth of 2 arguments does not match
        _pool.withdrawLiquidity(assetIds, amounts);
    }

    function _transferToLiquidityPool(uint8[] memory assetIds, uint256[] memory amounts) internal {
        _transferTo(address(_pool), assetIds, amounts);
        _pool.depositLiquidity(assetIds);
    }

    function _transferTo(
        address recipient,
        uint8[] memory assetIds,
        uint256[] memory amounts
    ) internal {
        uint256 length = assetIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (amounts[i] != 0) {
                IERC20Upgradeable asset = IERC20Upgradeable(_getAssetAddress(assetIds[i]));
                asset.safeTransfer(recipient, amounts[i]);
            }
        }
    }

    function _transferTo(
        address recipient,
        address[] memory assets,
        uint256[] memory amounts
    ) internal {
        uint256 length = assets.length;
        for (uint256 i = 0; i < length; i++) {
            if (amounts[i] != 0) {
                IERC20Upgradeable(assets[i]).safeTransfer(recipient, amounts[i]);
            }
        }
    }
}
