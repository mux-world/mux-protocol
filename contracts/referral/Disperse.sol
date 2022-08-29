// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../components/SafeOwnableUpgradeable.sol";

contract Disperse is SafeOwnableUpgradeable {
    using Address for address;
    using SafeERC20 for IERC20;

    enum TransferType {
        Rebate,
        Discount
    }

    address public token;
    address public maintainer;

    event DisperseReferrerRebate(
        address referrer,
        uint256 epoch,
        uint256 totalAmount,
        bytes32[] referralCodes,
        address[] recipients,
        uint256[] amounts,
        uint256 usdPrice
    );
    event DisperseTraderDiscount(
        uint256 epoch,
        uint256 totalAmount,
        address[] traders,
        uint256[] amounts,
        uint256 usdPrice
    );
    event Transfer(TransferType transferType, bytes32 referralCode, address recipient, uint256 amount);
    event WithdrawToken(address token, uint256 value);
    event SetMaintainer(address previousMaintainer, address newMaintainer);

    function initialize() external initializer {
        __SafeOwnable_init();
    }

    function setToken(address newToken) external onlyOwner {
        require(newToken != token, "Disperse::setMaintainer::Duplicated");
        emit SetMaintainer(token, newToken);
        token = newToken;
    }

    function setMaintainer(address newMaintainer) external onlyOwner {
        require(newMaintainer != maintainer, "Disperse::setMaintainer::Duplicated");
        emit SetMaintainer(maintainer, newMaintainer);
        maintainer = newMaintainer;
    }

    function disperseReferrerRebate(
        address referrer,
        uint256 epoch,
        bytes32[] memory referralCodes,
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 usdPrice
    ) external {
        require(token != address(0), "Disperse::disperseToken::TokenNotSet");
        require(msg.sender == maintainer, "Disperse::disperseToken::OnlyMaintainer");
        require(
            referralCodes.length == amounts.length && recipients.length == amounts.length,
            "Disperse::disperseToken::ParamLengthMismatch"
        );
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
        address lastRecipient = address(0);
        uint256 sum;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] != lastRecipient) {
                if (lastRecipient != address(0)) {
                    IERC20(token).safeTransfer(lastRecipient, sum);
                }
                sum = amounts[i];
                lastRecipient = recipients[i];
            } else {
                sum += amounts[i];
            }
            emit Transfer(TransferType.Rebate, referralCodes[i], recipients[i], amounts[i]);
        }
        if (lastRecipient != address(0)) {
            IERC20(token).safeTransfer(lastRecipient, sum);
        }
        emit DisperseReferrerRebate(referrer, epoch, totalAmount, referralCodes, recipients, amounts, usdPrice);
    }

    function disperseTraderDiscount(
        uint256 epoch,
        bytes32[] memory referralCodes,
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 usdPrice
    ) external {
        require(token != address(0), "Disperse::disperseToken::TokenNotSet");
        require(msg.sender == maintainer, "Disperse::disperseToken::OnlyMaintainer");
        require(
            recipients.length == referralCodes.length && recipients.length == amounts.length,
            "Disperse::disperseToken::ParamLengthMismatch"
        );

        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
        for (uint256 i = 0; i < recipients.length; i++) {
            IERC20(token).safeTransfer(recipients[i], amounts[i]);
            emit Transfer(TransferType.Discount, referralCodes[i], recipients[i], amounts[i]);
        }
        emit DisperseTraderDiscount(epoch, totalAmount, recipients, amounts, usdPrice);
    }

    function withdrawToken(IERC20 _token, uint256 value) external onlyOwner {
        _token.safeTransfer(msg.sender, value);
        emit WithdrawToken(address(_token), value);
    }
}
