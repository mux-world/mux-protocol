// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/ILiquidityPool.sol";
import "./Types.sol";
import "./Storage.sol";

contract AssetManager is Storage {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event FetchAssets(uint8[] assetIds, uint256[] amounts);
    event PushAssets(uint8[] assetIds, uint256[] amounts);
    event WithdrawToken(address token, address recipient, uint256 amount);

    modifier auth() {
        require(_handlers[msg.sender], "NHL"); // not handler
        _;
    }

    modifier onlyMaintainer() {
        require(msg.sender == _maintainer || msg.sender == owner(), "SND"); // invalid sender
        _;
    }

    function withdrawToken(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            AddressUpgradeable.sendValue(payable(msg.sender), amount);
        } else {
            IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
        }
        emit WithdrawToken(token, msg.sender, amount);
    }

    function _fetchAssets(uint8[] memory assetIds, uint256[] memory amounts) internal {
        require(assetIds.length == amounts.length, "LEN"); // LENgth of 2 arguments does not match
        ILiquidityPool(_pool).transferLiquidityOut(assetIds, amounts);
        emit FetchAssets(assetIds, amounts);
    }

    function _pushAssets(uint8[] memory assetIds, uint256[] memory amounts) internal {
        if (_transferTo(_pool, assetIds, amounts)) {
            ILiquidityPool(_pool).transferLiquidityIn(assetIds, amounts);
            emit PushAssets(assetIds, amounts);
        }
    }

    function _getDexTokens(uint8 dexId) internal view returns (address[] memory tokens) {
        uint8[] memory assetIds = _dexSpotConfigs[dexId].assetIds;
        tokens = new address[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; i++) {
            tokens[i] = _getTokenAddress(assetIds[i]);
        }
    }

    function _repayAssets(
        uint8 dexId,
        uint256[] memory maxAmounts,
        uint256[] memory usedAmounts
    ) internal returns (uint256[] memory remainAmounts) {
        require(maxAmounts.length == usedAmounts.length, "LEN"); // LENgth of 2 arguments does not match
        uint256 n = maxAmounts.length;
        remainAmounts = new uint256[](n);
        bool hasRemain = false;
        for (uint256 i = 0; i < n; i++) {
            if (maxAmounts[i] > usedAmounts[i]) {
                remainAmounts[i] = maxAmounts[i] - usedAmounts[i];
                hasRemain = true;
            }
        }
        _pushAssets(_dexSpotConfigs[dexId].assetIds, remainAmounts);
    }

    function _getTokenAddress(uint8 assetId) internal view returns (address token) {
        token = _tokenCache[assetId];
        require(token != address(0), "NAD");
    }

    function _tryGetTokenAddress(uint8 assetId) internal returns (address token) {
        token = _tokenCache[assetId];
        if (token == address(0)) {
            token = ILiquidityPool(_pool).getAssetAddress(assetId);
            _tokenCache[assetId] = token;
        }
    }

    function _transferTo(
        address recipient,
        uint8[] memory assetIds,
        uint256[] memory amounts
    ) internal returns (bool transferred) {
        require(assetIds.length == amounts.length, "LEN"); // LENgth of 2 arguments does not match
        for (uint256 i = 0; i < assetIds.length; i++) {
            if (amounts[i] != 0) {
                IERC20Upgradeable(_tryGetTokenAddress(assetIds[i])).safeTransfer(recipient, amounts[i]);
                transferred = true;
            }
        }
    }
}
