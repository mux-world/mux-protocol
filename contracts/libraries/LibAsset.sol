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

    function balanceOf(Asset storage token) internal view returns (uint256) {
        return IERC20Upgradeable(token.tokenAddress).balanceOf(address(this));
    }

    function calcTransferredBalance(Asset storage token) internal returns (uint256 rawAmount) {
        uint256 newBalance = balanceOf(token);
        uint256 oldBalance = uint256(token.tokenBalance);
        require(newBalance >= oldBalance, "B<B");
        rawAmount = newBalance - oldBalance;
        token.tokenBalance = newBalance.safeUint128();
    }

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
        token.tokenBalance = balanceOf(token).safeUint128();
    }

    function issueMuxToken(
        Asset storage token,
        address recipient,
        uint256 rawAmount
    ) internal {
        IERC20Upgradeable(token.muxTokenAddress).safeTransfer(recipient, rawAmount);
    }

    // TODO redeem
    // def repay_debt(self, collateral_id: Uint32, debt_raw_amount: Uint256):
    //     self._validate_collateral(collateral_id)
    //     debt_token = IERC20(self.assets[collateral_id].debt_token_address)
    //     debt_token.transfer(self.msg.sender, self.this, debt_raw_amount)
    //     debt_wad_amount = FixedU256(debt_raw_amount)

    //     require(self.assets[collateral_id].liquidity_balance >=
    //             debt_wad_amount, 'insufficient liquidity')
    //     raw_amount = self._from_wad(collateral_id, debt_wad_amount)
    //     self._push_collateral(self.msg.sender, collateral_id, raw_amount)

    //     # TODO: emit

    function toWad(Asset storage token, uint256 rawAmount) internal view returns (uint96) {
        return (rawAmount * (10**(18 - token.decimals))).safeUint96();
    }

    function toRaw(Asset storage token, uint96 wadAmount) internal view returns (uint256) {
        return uint256(wadAmount) / 10**(18 - token.decimals);
    }
}
