// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/ILiquidityPool.sol";
import "../../libraries/LibUtils.sol";
import "./Module.sol";

import "hardhat/console.sol";

/**
 * @notice This a a system module which defines how to move fund between `LiquidityPool` and `LiquidityManager`
 */
contract TransferModule is Module {
    using SafeERC20 for IERC20;

    function id() public pure override returns (bytes32) {
        return "transfer-mod";
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
        ids = new bytes32[](5);
        ids[0] = LibUtils.toBytes32("transferFromPool");
        ids[1] = LibUtils.toBytes32("transferToPool");
        ids[2] = LibUtils.toBytes32("transferToVault");
        ids[3] = LibUtils.toBytes32("transferFromPoolByDex");
        ids[4] = LibUtils.toBytes32("transferToPoolByDex");
        selectors = new bytes4[](5);
        selectors[0] = this.transferFromPool.selector;
        selectors[1] = this.transferToPool.selector;
        selectors[2] = this.transferToVault.selector;
        selectors[3] = this.transferFromPoolByDex.selector;
        selectors[4] = this.transferToPoolByDex.selector;
        initialStates = new bytes32[](0);
    }

    function transferFromPoolByDex(uint8 dexId, uint256[] memory amounts) external {
        uint8[] memory assetIds = _getDexSpotConfig(dexId).assetIds;
        transferFromPool(assetIds, amounts);
    }

    function transferToPoolByDex(uint8 dexId, uint256[] memory amounts) external {
        uint8[] memory assetIds = _getDexSpotConfig(dexId).assetIds;
        require(assetIds.length == amounts.length, "LEN"); // LENgth of 2 arguments does not match
        transferToPool(assetIds, amounts);
    }

    function transferFromPool(uint8[] memory assetIds, uint256[] memory amounts) public {
        require(assetIds.length == amounts.length, "LEN"); // LENgth of 2 arguments does not match
        ILiquidityPool(_pool).transferLiquidityOut(assetIds, amounts);
    }

    function transferToPool(uint8[] memory assetIds, uint256[] memory amounts) public {
        _transferTo(_pool, assetIds, amounts);
        ILiquidityPool(_pool).transferLiquidityIn(assetIds, amounts);
    }

    function transferToVault(address[] memory assets, uint256[] memory amounts) external {
        _transferTo(_vault, assets, amounts);
    }

    function _transferTo(
        address recipient,
        uint8[] memory assetIds,
        uint256[] memory amounts
    ) internal {
        uint256 length = assetIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (amounts[i] != 0) {
                IERC20 token = IERC20(_getTokenAddr(assetIds[i]));
                token.safeTransfer(recipient, amounts[i]);
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
                IERC20(assets[i]).safeTransfer(recipient, amounts[i]);
            }
        }
    }

    function _getTokenAddr(uint8 assetId) internal view returns (address) {
        return ILiquidityPool(_pool).getAssetAddress(assetId);
    }
}
