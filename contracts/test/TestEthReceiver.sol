// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

interface IOrderBook {
    struct PositionOrderExtra {
        // tp/sl strategy
        uint96 tpPrice; // take-profit price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
        uint96 slPrice; // stop-loss price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
        uint8 tpslProfitTokenId; // only valid when flags.POSITION_TPSL_STRATEGY.
        uint32 tpslDeadline; // only valid when flags.POSITION_TPSL_STRATEGY.
    }

    function placePositionOrder3(
        bytes32 subAccountId,
        uint96 collateralAmount, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline, // 1e0
        bytes32 referralCode,
        PositionOrderExtra memory extra
    ) external payable;
}

contract TestEthReceiver {
    bool public enableGasDepletion;
    uint256 public gas;
    address public orderBook;

    constructor(address orderBook_) {
        orderBook = orderBook_;
    }

    function setGasDepletion(bool state) public {
        enableGasDepletion = state;
    }

    receive() external payable {
        gas = gasleft();
        if (enableGasDepletion) {
            for (uint256 i = 0; i < type(uint256).max; i++) {}
        }
    }

    function placePositionOrder3(
        bytes32 subAccountId,
        uint96 collateralAmount, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline, // 1e0
        bytes32 referralCode,
        IOrderBook.PositionOrderExtra memory extra
    ) external payable {
        IOrderBook(orderBook).placePositionOrder3{ value: msg.value }(
            subAccountId,
            collateralAmount, // erc20.decimals
            size, // 1e18
            price, // 1e18
            profitTokenId,
            flags,
            deadline, // 1e0
            referralCode,
            extra
        );
    }
}
