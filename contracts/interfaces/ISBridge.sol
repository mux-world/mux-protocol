// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

interface ISBridge {
    function transfer(
        address token,
        uint256 amount,
        uint256 destChain
    ) external;

    function claim(
        uint256 sourceChain,
        uint256 messageID,
        address receiver,
        address token,
        uint256 amount
    ) external;
}
