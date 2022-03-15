// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

enum OrderType {
    None, // 0
    PositionOrder, // 1
    LiquidityOrder, // 2
    WithdrawalOrder // 3
}

// +-------+--------------------+-----------+-----------+-----------+
// | index |                    |           |           | remaining |
// +-------+--------------------+-----------+-----------+-----------+
// | 0     | subAccountId (184) | orderId (64) | padding (4) | type (4) | 4    |
// +-------+--------------------+-----------+-----------+-----------+
// | 1     | collateral (96)    | size (96) | flags (8) | 56        |
// +-------+--------------------+-----------+-----------+-----------+
// | 2     | price (96)         |           |           | 192       |
// +-------+--------------------+-----------+-----------+-----------+
struct PositionOrder {
    uint64 id;
    bytes32 subAccountId; // 160 + 8 + 8 + 8 = 184
    uint96 collateral; // 96
    uint96 size; // 96
    uint96 price; // 96
    uint8 profitTokenId; // 8
    uint8 flags; // 8
}

// +-------+--------------------+-----------+-----------+-----------+
// | index |                    |           |           | remaining |
// +-------+--------------------+-----------+-----------+-----------+
// | 0     | account (160)      | padding (24) | orderId (64) | padding (4)  |  type (4)    | 28 |
// +-------+--------------------+-----------+-----------+-----------+
// | 1     | amount (96)        | assetId (96)  | flags (8) | 56    |
// +-------+--------------------+-----------+-----------+-----------+
struct LiquidityOrder {
    uint64 id;
    address account; // 160
    uint96 amount; // 96
    uint8 assetId; // 32
    bool isAdding; // 8
}

// +-------+--------------------+-----------+-----------+--------------+
// | index |                    |           |              | remaining |
// +-------+--------------------+-----------+-----------+--------------+
// | 0     | subAccountId (184) | orderId (64) | padding (4) | type (4) | 4    |
// | 1     | amount (96)  | profitTokenId(32)  | withProfit (8)  | 24  |
// +-------+--------------------+-----------+-----------+--------------+
struct WithdrawalOrder {
    uint64 id;
    bytes32 subAccountId; // 184
    uint96 amount; // 96
    uint8 profitTokenId; // 32
    bool isProfit;
}
