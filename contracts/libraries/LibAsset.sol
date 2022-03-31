// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/IWETH9.sol";
import "../libraries/LibMath.sol";
import "../core/Types.sol";

library LibAsset {
    using LibMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    function transferOut(
        Asset storage token,
        address recipient,
        uint256 rawAmount,
        address weth
    ) internal {
        if (token.tokenAddress == weth) {
            IWETH(weth).withdraw(rawAmount);
            AddressUpgradeable.sendValue(payable(recipient), rawAmount);
        } else {
            IERC20Upgradeable(token.tokenAddress).safeTransfer(recipient, rawAmount);
        }
    }

    function issueMuxToken(
        Asset storage token,
        address recipient,
        uint256 muxTokenAmount
    ) internal {
        IERC20Upgradeable(token.muxTokenAddress).safeTransfer(recipient, muxTokenAmount);
    }

    function toWad(Asset storage token, uint256 rawAmount) internal view returns (uint96) {
        return (rawAmount * (10**(18 - token.decimals))).safeUint96();
    }

    function toRaw(Asset storage token, uint96 wadAmount) internal view returns (uint256) {
        return uint256(wadAmount) / 10**(18 - token.decimals);
    }
}
