// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../libraries/LibSubAccount.sol";
import "../libraries/LibMath.sol";
import "../interfaces/IReferralManager.sol";
import "../orderbook/Types.sol";
import "../orderbook/Storage.sol";

library LibOrderBook {
    using LibSubAccount for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibOrder for LibOrder.OrderList;
    using LibOrder for bytes32[3];
    using LibOrder for PositionOrder;
    using LibOrder for LiquidityOrder;
    using LibOrder for WithdrawalOrder;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using LibMath for uint256;

    uint256 public constant MAX_TP_SL_ORDERS = 32;

    // do not forget to update OrderBook if this line updates
    event CancelOrder(uint64 orderId, OrderType orderType, bytes32[3] orderData);
    // do not forget to update OrderBook if this line updates
    event NewLiquidityOrder(
        address indexed account,
        uint64 indexed orderId,
        uint8 assetId,
        uint96 rawAmount, // erc20.decimals
        bool isAdding
    );
    // do not forget to update OrderBook if this line updates
    event NewPositionOrder(
        bytes32 indexed subAccountId,
        uint64 indexed orderId,
        uint96 collateral, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline // 1e0. 0 if market order. > 0 if limit order
    );
    // do not forget to update OrderBook if this line updates
    event NewPositionOrderExtra(
        bytes32 indexed subAccountId,
        uint64 indexed orderId,
        uint96 collateral, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline, // 1e0. 0 if market order. > 0 if limit order
        PositionOrderExtra extra
    );

    function _transferIn(
        OrderBookStorage storage _storage,
        address trader,
        address tokenAddress,
        address recipient,
        uint256 rawAmount
    ) internal {
        if (tokenAddress == address(_storage.weth)) {
            require(msg.value > 0 && msg.value == rawAmount, "VAL"); // transaction VALue SHOULD equal to rawAmount
            _storage.weth.deposit{ value: rawAmount }();
            if (recipient != address(this)) {
                _storage.weth.transfer(recipient, rawAmount);
            }
        } else {
            require(msg.value == 0, "VAL"); // transaction VALue SHOULD be 0
            IERC20Upgradeable(tokenAddress).safeTransferFrom(trader, recipient, rawAmount);
        }
    }

    function _transferOut(
        OrderBookStorage storage _storage,
        address tokenAddress,
        address recipient,
        uint256 rawAmount
    ) internal {
        if (tokenAddress == address(_storage.weth)) {
            _storage.weth.transfer(address(_storage.nativeUnwrapper), rawAmount);
            INativeUnwrapper(_storage.nativeUnwrapper).unwrap(payable(recipient), rawAmount);
        } else {
            IERC20Upgradeable(tokenAddress).safeTransfer(recipient, rawAmount);
        }
    }

    function placeLiquidityOrder(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        address account,
        uint8 assetId,
        uint96 rawAmount, // erc20.decimals
        bool isAdding
    ) external {
        // require(rawAmount != 0, "A=0"); // Amount Is Zero
        if (rawAmount != 0) {
            if (isAdding) {
                address collateralAddress = _storage.pool.getAssetAddress(assetId);
                _transferIn(_storage, account, collateralAddress, address(this), rawAmount);
            } else {
                _storage.mlp.safeTransferFrom(account, address(this), rawAmount);
            }
        } else {
            require(_storage.callbackWhitelist[account], "NCB");
        }
        uint64 orderId = _storage.nextOrderId++;
        bytes32[3] memory data = LibOrder.encodeLiquidityOrder(
            orderId,
            account,
            assetId,
            rawAmount,
            isAdding,
            blockTimestamp
        );
        _storage.orders.add(orderId, data);

        emit NewLiquidityOrder(account, orderId, assetId, rawAmount, isAdding);
    }

    function fillLiquidityOrder(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        uint96 assetPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue,
        bytes32[3] memory orderData
    ) external returns (uint256 outAmount) {
        LiquidityOrder memory order = orderData.decodeLiquidityOrder();
        require(blockTimestamp >= order.placeOrderTime + _storage.liquidityLockPeriod, "LCK"); // mlp token is LoCKed
        uint96 rawAmount = order.rawAmount;
        if (order.isAdding) {
            IERC20Upgradeable collateral = IERC20Upgradeable(_storage.pool.getAssetAddress(order.assetId));
            collateral.safeTransfer(address(_storage.pool), rawAmount);
            outAmount = _storage.pool.addLiquidity(
                order.account,
                order.assetId,
                rawAmount,
                assetPrice,
                mlpPrice,
                currentAssetValue,
                targetAssetValue
            );
        } else {
            _storage.mlp.safeTransfer(address(_storage.pool), rawAmount);
            outAmount = _storage.pool.removeLiquidity(
                order.account,
                rawAmount,
                order.assetId,
                assetPrice,
                mlpPrice,
                currentAssetValue,
                targetAssetValue
            );
        }
    }

    function redeemMuxToken(
        OrderBookStorage storage _storage,
        address trader,
        uint8 tokenId,
        uint96 muxTokenAmount
    ) external {
        Asset memory asset = _storage.pool.getAssetInfo(tokenId);
        _transferIn(_storage, trader, asset.muxTokenAddress, address(_storage.pool), muxTokenAmount);
        _storage.pool.redeemMuxToken(trader, tokenId, muxTokenAmount);
    }

    function cancelActivatedTpslOrders(OrderBookStorage storage _storage, bytes32 subAccountId) public {
        EnumerableSetUpgradeable.UintSet storage orderIds = _storage.activatedTpslOrders[subAccountId];
        uint256 length = orderIds.length();
        for (uint256 i = 0; i < length; i++) {
            uint64 orderId = uint64(orderIds.at(i));
            require(_storage.orders.contains(orderId), "OID"); // can not find this OrderID
            bytes32[3] memory orderData = _storage.orders.get(orderId);
            _storage.orders.remove(orderId);

            OrderType orderType = LibOrder.getOrderType(orderData);
            require(orderType == OrderType.PositionOrder, "TYP"); // order TYPe mismatch

            PositionOrder memory order = orderData.decodePositionOrder();
            require(!order.isOpenPosition() && order.collateral == 0, "CLS"); // should be CLoSe position order and no withdraw

            delete _storage.positionOrderExtras[orderId]; // tp/sl strategy

            emit CancelOrder(orderId, orderType, orderData);
        }

        delete _storage.activatedTpslOrders[subAccountId]; // tp/sl strategy
    }

    function placePositionOrder(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        bytes32 subAccountId,
        uint96 collateralAmount, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline, // 1e0
        PositionOrderExtra memory extra
    ) external {
        require(size != 0, "S=0"); // order Size Is Zero
        if ((flags & LibOrder.POSITION_MARKET_ORDER) != 0) {
            require(price == 0, "P!0"); // market order does not need a limit Price
            require(deadline == 0, "D!0"); // market order does not need a deadline
        } else {
            require(deadline > blockTimestamp, "D<0"); // Deadline is earlier than now
        }
        if (profitTokenId > 0) {
            // note: profitTokenId == 0 is also valid, this only partially protects the function from misuse
            require((flags & LibOrder.POSITION_OPEN) == 0, "T!0"); // opening position does not need a profit Token id
        }
        if ((flags & LibOrder.POSITION_OPEN) != 0) {
            _placeOpenPositionOrder(
                _storage,
                blockTimestamp,
                subAccountId,
                collateralAmount,
                size,
                price,
                flags,
                deadline,
                extra
            );
        } else {
            _placeClosePositionOrder(
                _storage,
                blockTimestamp,
                subAccountId,
                collateralAmount,
                size,
                price,
                profitTokenId,
                flags,
                deadline,
                extra
            );
        }
    }

    function _placeOpenPositionOrder(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        bytes32 subAccountId,
        uint96 collateralAmount, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 flags,
        uint32 deadline, // 1e0
        PositionOrderExtra memory extra
    ) private {
        // add order
        uint64 orderId = _placePositionOrder(
            _storage,
            blockTimestamp,
            deadline,
            PositionOrder({
                id: 0, // ignored
                subAccountId: subAccountId,
                collateral: collateralAmount,
                size: size,
                price: price,
                profitTokenId: 0, // open-position-order does not have a profitTokenId
                flags: flags,
                placeOrderTime: 0, // ignored
                expire10s: 0 // ignored
            })
        );
        // fetch collateral
        if (collateralAmount > 0) {
            address accountOwner = subAccountId.getSubAccountOwner();
            uint8 collateralId = subAccountId.getSubAccountCollateralId();
            address collateralAddress = _storage.pool.getAssetAddress(collateralId);
            _transferIn(_storage, accountOwner, collateralAddress, address(this), collateralAmount);
        }
        if ((flags & LibOrder.POSITION_TPSL_STRATEGY) != 0) {
            // tp/sl strategy
            require((extra.tpPrice > 0 || extra.slPrice > 0), "TPSL"); // TP/SL strategy need tpPrice and/or slPrice
            require(extra.tpslDeadline > blockTimestamp, "D<0"); // Deadline is earlier than now
            require((extra.tpslDeadline - blockTimestamp) / 10 <= type(uint24).max, "DTL"); // Deadline is Too Large
            _storage.positionOrderExtras[orderId] = extra;
            emit NewPositionOrderExtra(
                subAccountId,
                orderId,
                collateralAmount,
                size,
                price,
                0 /* profitTokenId */,
                flags,
                deadline,
                extra
            );
        }
    }

    function _placeClosePositionOrder(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        bytes32 subAccountId,
        uint96 collateralAmount, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline, // 1e0
        PositionOrderExtra memory extra
    ) private {
        if ((flags & LibOrder.POSITION_TPSL_STRATEGY) != 0) {
            // tp/sl strategy
            require(price == 0, "P!0"); // use extra.tpPrice and extra.slPrice instead
            require(collateralAmount == 0, "C!0"); // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
            require(profitTokenId == 0, "T!0"); // use extra.tpProfitTokenId instead
            require((flags & LibOrder.POSITION_MARKET_ORDER) == 0, "MKT"); // tp/sl strategy does not support MarKeT order
            require(extra.tpPrice > 0 && extra.slPrice > 0, "TPSL"); // tp/sl strategy need tpPrice and slPrice. otherwise use POSITION_TRIGGER_ORDER instead
            require(extra.tpslDeadline > blockTimestamp, "D<0"); // Deadline is earlier than now
            require((extra.tpslDeadline - blockTimestamp) / 10 <= type(uint24).max, "DTL"); // Deadline is Too Large
            _placeTpslOrdersWhenClose(_storage, blockTimestamp, subAccountId, size, extra);
        } else {
            // normal close-position-order
            if (flags & LibOrder.POSITION_SHOULD_REACH_MIN_PROFIT != 0) {
                // POSITION_MUST_PROFIT is only available if asset.minProfitTime > 0
                uint8 assetId = subAccountId.getSubAccountAssetId();
                Asset memory asset = _storage.pool.getAssetInfo(assetId);
                require(asset.minProfitTime > 0, "MPT"); // asset MinProfitTime is 0
            }
            _placePositionOrder(
                _storage,
                blockTimestamp,
                deadline,
                PositionOrder({
                    id: 0, // ignored
                    subAccountId: subAccountId,
                    collateral: collateralAmount,
                    size: size,
                    price: price,
                    profitTokenId: profitTokenId,
                    flags: flags,
                    placeOrderTime: 0, // ignored
                    expire10s: 0 // ignored
                })
            );
        }
    }

    function _placePositionOrder(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        uint32 deadline, // 1e0. NOTE: deadline should be 0 for market order; > _blockTimestamp() for limit/trigger order
        PositionOrder memory order // NOTE: id, placeOrderTime, expire10s will be ignored
    ) private returns (uint64 newOrderId) {
        uint32 expire10s;
        if (deadline > 0) {
            expire10s = (deadline - blockTimestamp) / 10;
            require(expire10s <= type(uint24).max, "DTL"); // Deadline is Too Large
        }
        newOrderId = _storage.nextOrderId++;
        bytes32[3] memory newOrderData = LibOrder.encodePositionOrder(
            newOrderId,
            order.subAccountId,
            order.collateral,
            order.size,
            order.price,
            order.profitTokenId,
            order.flags,
            blockTimestamp,
            uint24(expire10s)
        );
        _storage.orders.add(newOrderId, newOrderData);
        emit NewPositionOrder(
            order.subAccountId,
            newOrderId,
            order.collateral,
            order.size,
            order.price,
            order.profitTokenId,
            order.flags,
            deadline
        );
    }

    function fillOpenPositionOrder(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        uint64 orderId,
        uint96 collateralPrice,
        uint96 assetPrice,
        PositionOrder memory order
    ) external returns (uint96 tradingPrice) {
        // auto deposit
        uint96 collateralAmount = order.collateral;
        if (collateralAmount > 0) {
            IERC20Upgradeable collateral = IERC20Upgradeable(
                _storage.pool.getAssetAddress(order.subAccountId.getSubAccountCollateralId())
            );
            collateral.safeTransfer(address(_storage.pool), collateralAmount);
            _storage.pool.depositCollateral(order.subAccountId, collateralAmount);
        }
        // open
        tradingPrice = _storage.pool.openPosition(order.subAccountId, order.size, collateralPrice, assetPrice);
        // tp/sl strategy
        if (order.isTpslStrategy()) {
            PositionOrderExtra memory extra = _storage.positionOrderExtras[orderId];
            delete _storage.positionOrderExtras[orderId];
            _placeTpslOrdersWhenOpen(_storage, blockTimestamp, order, extra);
        }
    }

    function fillClosePositionOrder(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        uint64 orderId,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice, // only used when !isLong
        PositionOrder memory order
    ) external returns (uint96 tradingPrice) {
        // check min profit
        SubAccount memory oldSubAccount;
        if (order.shouldReachMinProfit()) {
            (
                oldSubAccount.collateral,
                oldSubAccount.size,
                oldSubAccount.lastIncreasedTime,
                oldSubAccount.entryPrice,
                oldSubAccount.entryFunding
            ) = _storage.pool.getSubAccount(order.subAccountId);
        }
        // close
        tradingPrice = _storage.pool.closePosition(
            order.subAccountId,
            order.size,
            order.profitTokenId,
            collateralPrice,
            assetPrice,
            profitAssetPrice
        );
        // check min profit
        if (order.shouldReachMinProfit()) {
            require(_hasPassMinProfit(_storage, order, blockTimestamp, oldSubAccount, tradingPrice), "PFT"); // order must have ProFiT
        }
        // auto withdraw
        uint96 collateralAmount = order.collateral;
        if (collateralAmount > 0) {
            _storage.pool.withdrawCollateral(order.subAccountId, collateralAmount, collateralPrice, assetPrice);
        }
        // tp/sl strategy
        _storage.activatedTpslOrders[order.subAccountId].remove(uint256(orderId));
        // is the position completely closed
        (uint96 collateral, uint96 size, , , ) = _storage.pool.getSubAccount(order.subAccountId);
        if (size == 0) {
            // auto withdraw
            if (order.isWithdrawIfEmpty() && collateral > 0) {
                _storage.pool.withdrawAllCollateral(order.subAccountId);
            }

            // cancel activated tp/sl orders
            cancelActivatedTpslOrders(_storage, order.subAccountId);
        }
    }

    function _placeTpslOrdersWhenOpen(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        PositionOrder memory order,
        PositionOrderExtra memory extra
    ) private {
        if (extra.tpPrice > 0) {
            uint8 flags = LibOrder.POSITION_WITHDRAW_ALL_IF_EMPTY;
            uint8 assetId = order.subAccountId.getSubAccountAssetId();
            Asset memory asset = _storage.pool.getAssetInfo(assetId);
            if (asset.minProfitTime > 0) {
                flags |= LibOrder.POSITION_SHOULD_REACH_MIN_PROFIT;
            }
            uint64 orderId = _placePositionOrder(
                _storage,
                blockTimestamp,
                extra.tpslDeadline,
                PositionOrder({
                    id: 0, // ignored
                    subAccountId: order.subAccountId,
                    collateral: 0, // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
                    size: order.size,
                    price: extra.tpPrice,
                    profitTokenId: extra.tpslProfitTokenId,
                    flags: flags,
                    placeOrderTime: 0, // ignored
                    expire10s: 0 // ignored
                })
            );
            _storage.activatedTpslOrders[order.subAccountId].add(uint256(orderId));
            require(_storage.activatedTpslOrders[order.subAccountId].length() <= MAX_TP_SL_ORDERS, "TMO"); // Too Many TP/SL Orders
        }
        if (extra.slPrice > 0) {
            uint64 orderId = _placePositionOrder(
                _storage,
                blockTimestamp,
                extra.tpslDeadline,
                PositionOrder({
                    id: 0, // ignored
                    subAccountId: order.subAccountId,
                    collateral: 0, // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
                    size: order.size,
                    price: extra.slPrice,
                    profitTokenId: extra.tpslProfitTokenId,
                    flags: LibOrder.POSITION_WITHDRAW_ALL_IF_EMPTY | LibOrder.POSITION_TRIGGER_ORDER,
                    placeOrderTime: 0, // ignored
                    expire10s: 0 // ignored
                })
            );
            _storage.activatedTpslOrders[order.subAccountId].add(uint256(orderId));
            require(_storage.activatedTpslOrders[order.subAccountId].length() <= MAX_TP_SL_ORDERS, "TMO"); // Too Many TP/SL Orders
        }
    }

    function _placeTpslOrdersWhenClose(
        OrderBookStorage storage _storage,
        uint32 blockTimestamp,
        bytes32 subAccountId,
        uint96 size, // 1e18
        PositionOrderExtra memory extra
    ) private {
        if (extra.tpPrice > 0) {
            uint8 flags = LibOrder.POSITION_WITHDRAW_ALL_IF_EMPTY;
            uint8 assetId = subAccountId.getSubAccountAssetId();
            Asset memory asset = _storage.pool.getAssetInfo(assetId);
            if (asset.minProfitTime > 0) {
                flags |= LibOrder.POSITION_SHOULD_REACH_MIN_PROFIT;
            }
            uint64 orderId = _placePositionOrder(
                _storage,
                blockTimestamp,
                extra.tpslDeadline,
                PositionOrder({
                    id: 0, // ignored
                    subAccountId: subAccountId,
                    collateral: 0, // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
                    size: size,
                    price: extra.tpPrice,
                    profitTokenId: extra.tpslProfitTokenId,
                    flags: flags,
                    placeOrderTime: 0, // ignored
                    expire10s: 0 // ignored
                })
            );
            _storage.activatedTpslOrders[subAccountId].add(uint256(orderId));
            require(_storage.activatedTpslOrders[subAccountId].length() <= MAX_TP_SL_ORDERS, "TMO"); // Too Many TP/SL Orders
        }
        if (extra.slPrice > 0) {
            uint64 orderId = _placePositionOrder(
                _storage,
                blockTimestamp,
                extra.tpslDeadline,
                PositionOrder({
                    id: 0, // ignored
                    subAccountId: subAccountId,
                    collateral: 0, // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
                    size: size,
                    price: extra.slPrice,
                    profitTokenId: extra.tpslProfitTokenId,
                    flags: LibOrder.POSITION_WITHDRAW_ALL_IF_EMPTY | LibOrder.POSITION_TRIGGER_ORDER,
                    placeOrderTime: 0, // ignored
                    expire10s: 0 // ignored
                })
            );
            _storage.activatedTpslOrders[subAccountId].add(uint256(orderId));
            require(_storage.activatedTpslOrders[subAccountId].length() <= MAX_TP_SL_ORDERS, "TMO"); // Too Many TP/SL Orders
        }
    }

    function _hasPassMinProfit(
        OrderBookStorage storage _storage,
        PositionOrder memory order,
        uint32 blockTimestamp,
        SubAccount memory oldSubAccount,
        uint96 tradingPrice
    ) private view returns (bool) {
        if (oldSubAccount.size == 0) {
            return true;
        }
        LibSubAccount.DecodedSubAccountId memory decoded = order.subAccountId.decodeSubAccountId();
        require(tradingPrice > 0, "P=0"); // Price Is Zero
        bool hasProfit = decoded.isLong
            ? tradingPrice > oldSubAccount.entryPrice
            : tradingPrice < oldSubAccount.entryPrice;
        if (!hasProfit) {
            return true;
        }
        Asset memory asset = _storage.pool.getAssetInfo(decoded.assetId);
        if (blockTimestamp >= oldSubAccount.lastIncreasedTime + asset.minProfitTime) {
            return true;
        }
        uint96 priceDelta = tradingPrice >= oldSubAccount.entryPrice
            ? tradingPrice - oldSubAccount.entryPrice
            : oldSubAccount.entryPrice - tradingPrice;
        if (priceDelta >= uint256(oldSubAccount.entryPrice).rmul(asset.minProfitRate).safeUint96()) {
            return true;
        }
        return false;
    }
}
