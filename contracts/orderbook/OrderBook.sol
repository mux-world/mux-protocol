// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./Types.sol";
import "./Admin.sol";
import "../libraries/LibSubAccount.sol";

contract OrderBook is Storage, Admin {
    using LibSubAccount for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibOrder for LibOrder.OrderList;
    using LibOrder for bytes32[3];
    using LibOrder for PositionOrder;
    using LibOrder for LiquidityOrder;
    using LibOrder for WithdrawalOrder;

    event NewPositionOrder(
        bytes32 indexed subAccountId,
        uint64 indexed orderId,
        uint96 collateral,
        uint96 size,
        uint96 price,
        uint8 profitTokenId,
        uint8 flags
    );
    event NewLiquidityOrder(
        address indexed account,
        uint64 indexed orderId,
        uint8 assetId,
        uint96 amount,
        bool isAdding
    );
    event NewWithdrawalOrder(
        bytes32 indexed subAccountId,
        uint64 indexed orderId,
        uint96 amount,
        uint8 profitTokenId,
        bool isProfit
    );
    event FillOrder(uint64 orderId, OrderType orderType, bytes32[3] orderData);
    event CancelOrder(uint64 orderId, OrderType orderType, bytes32[3] orderData);

    function initialize(
        address pool,
        address mlp,
        address weth,
        address nativeUnwrapper
    ) external initializer {
        __SafeOwnable_init();

        _pool = ILiquidityPool(pool);
        _mlp = IERC20Upgradeable(mlp);
        _weth = IWETH(weth);
        _nativeUnwrapper = INativeUnwrapper(nativeUnwrapper);
    }

    function getOrderCount() external view returns (uint256) {
        return _orders.length();
    }

    function getOrder(uint64 orderId) external view returns (bytes32[3] memory, bool) {
        return (_orders.get(orderId), _orders.contains(orderId));
    }

    function getOrders(uint256 begin, uint256 end)
        external
        view
        returns (bytes32[3][] memory orderArray, uint256 totalCount)
    {
        totalCount = _orders.length();
        if (begin >= end || begin >= totalCount) {
            return (orderArray, totalCount);
        }
        end = end <= totalCount ? end : totalCount;
        uint256 size = end - begin;
        orderArray = new bytes32[3][](size);
        for (uint256 i = 0; i < size; i++) {
            orderArray[i] = _orders.at(i + begin);
        }
    }

    /**
     * @dev   Open/close position. called by Trader
     *
     * @param subAccountId       sub account id. see LibSubAccount.decodeSubAccountId
     * @param collateralAmount   deposit collateral before open; or withdraw collateral after close. decimals = erc20.decimals
     * @param size               position size. decimals = 18
     * @param price              limit price. decimals = 18
     * @param profitTokenId      specify the profitable asset.id when closing a position and making a profit.
     *                           take no effect when opening a position or loss.
     * @param flags              a bitset of LibOrder.POSITION_*
     *                           POSITION_INCREASING               1 for openPosition, 0 for closePosition
     *                           POSITION_MARKET_ORDER             ignore limitPrice
     *                           POSITION_WITHDRAW_ALL_IF_EMPTY    auto withdraw all if position.size == 0
     */
    function placePositionOrder(
        bytes32 subAccountId,
        uint96 collateralAmount,
        uint96 size,
        uint96 price,
        uint8 profitTokenId,
        uint8 flags
    ) external payable {
        LibSubAccount.DecodedSubAccountId memory account = subAccountId.decodeSubAccountId();
        require(account.account == msg.sender, "SND"); // SeNDer is not authorized
        require(size != 0, "S=0"); // order Size Is Zero
        if ((flags & LibOrder.POSITION_MARKET_ORDER) != 0) {
            require(price == 0, "P!0"); // market order does not need a limit Price
        }
        if (profitTokenId > 0) {
            // note: profitTokenId == 0 is also valid, this only partially protects the function from misuse
            require((flags & LibOrder.POSITION_INCREASING) == 0, "T!0"); // opening position does not need a Token id
        }
        // add order
        uint64 orderId = _nextOrderId++;
        bytes32[3] memory data = LibOrder.encodePositionOrder(
            orderId,
            subAccountId,
            collateralAmount,
            size,
            price,
            profitTokenId,
            flags
        );
        _orders.add(orderId, data);
        // fetch collateral
        if (collateralAmount > 0 && ((flags & LibOrder.POSITION_INCREASING) != 0)) {
            address collateralAddress = _pool.getAssetAddress(account.collateralId);
            _transferIn(collateralAddress, address(this), collateralAmount);
        }
        emit NewPositionOrder(subAccountId, orderId, collateralAmount, size, price, profitTokenId, flags);
    }

    /**
     * @dev   Add/remove liquidity. called by Liquidity Provider
     *
     * @param assetId   asset.id that added/removed to
     * @param amount    asset token amount. decimals = erc20.decimals
     * @param isAdding  true for add liquidity, false for remove liquidity
     */
    function placeLiquidityOrder(
        uint8 assetId,
        uint96 amount,
        bool isAdding
    ) external payable {
        require(amount != 0, "A=0"); // Amount Is Zero
        address account = msg.sender;
        if (isAdding) {
            address collateralAddress = _pool.getAssetAddress(assetId);
            _transferIn(collateralAddress, address(this), amount);
        } else {
            _mlp.safeTransferFrom(msg.sender, address(this), amount);
        }
        uint64 orderId = _nextOrderId++;
        bytes32[3] memory data = LibOrder.encodeLiquidityOrder(
            orderId,
            account,
            assetId,
            amount,
            isAdding,
            _blockTimestamp()
        );
        _orders.add(orderId, data);

        emit NewLiquidityOrder(account, orderId, assetId, amount, isAdding);
    }

    /**
     * @dev   Withdraw collateral/profit. called by Trader
     *
     * @param subAccountId       sub account id. see LibSubAccount.decodeSubAccountId
     * @param amount             collateral or profit asset amount. decimals = erc20.decimals
     * @param profitTokenId      specify the profitable asset.id
     * @param isProfit           true for withdraw profit. false for withdraw collateral
     */
    function placeWithdrawalOrder(
        bytes32 subAccountId,
        uint96 amount,
        uint8 profitTokenId,
        bool isProfit
    ) external {
        address trader = subAccountId.getSubAccountOwner();
        require(trader == msg.sender, "SND"); // SeNDer is not authorized
        require(amount != 0, "A=0"); // Amount Is Zero

        uint64 orderId = _nextOrderId++;
        bytes32[3] memory data = LibOrder.encodeWithdrawalOrder(orderId, subAccountId, amount, profitTokenId, isProfit);
        _orders.add(orderId, data);

        emit NewWithdrawalOrder(subAccountId, orderId, amount, profitTokenId, isProfit);
    }

    /**
     * @dev   Open/close a position. called by Broker
     *
     * @param orderId           order id
     * @param collateralPrice   collateral price. decimals = 18
     * @param assetPrice        asset price. decimals = 18
     * @param profitAssetPrice  profit asset price. decimals = 18
     */
    function fillPositionOrder(
        uint64 orderId,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external onlyBroker {
        require(_orders.contains(orderId), "OID"); // can not find this OrderID
        bytes32[3] memory orderData = _orders.get(orderId);
        _orders.remove(orderId);
        OrderType orderType = LibOrder.getOrderType(orderData);
        require(orderType == OrderType.PositionOrder, "TYP"); // order TYPe mismatch

        PositionOrder memory order = orderData.decodePositionOrder();
        if (!order.isMarketOrder()) {
            //             long                        !long
            // increase    assetPrice <= orderPrice    assetPrice >= orderPrice
            // !increase   assetPrice >= orderPrice    assetPrice <= orderPrice
            bool isLimitPriceOk;
            if (order.subAccountId.isLong() == order.isIncreasing()) {
                isLimitPriceOk = assetPrice <= order.price;
            } else {
                isLimitPriceOk = assetPrice >= order.price;
            }
            require(isLimitPriceOk, "LMT"); // LiMiTed by limitPrice
        }
        if (order.isIncreasing()) {
            // auto deposit
            uint96 collateralAmount = order.collateral;
            if (collateralAmount > 0) {
                IERC20Upgradeable collateral = IERC20Upgradeable(
                    _pool.getAssetAddress(order.subAccountId.getSubAccountCollateralId())
                );
                collateral.safeTransfer(address(_pool), collateralAmount);
                _pool.depositCollateral(order.subAccountId, collateralAmount);
            }
            _pool.openPosition(order.subAccountId, order.size, collateralPrice, assetPrice);
        } else {
            _pool.closePosition(
                order.subAccountId,
                order.size,
                order.profitTokenId,
                collateralPrice,
                assetPrice,
                profitAssetPrice
            );

            // auto withdraw
            uint96 collateralAmount = order.collateral;
            if (collateralAmount > 0) {
                _pool.withdrawCollateral(order.subAccountId, collateralAmount, collateralPrice, assetPrice);
            }
            if (order.isWithdrawIfEmpty()) {
                (uint96 collateral, uint96 size, , , ) = _pool.getSubAccount(order.subAccountId);
                if (size == 0 && collateral > 0) {
                    _pool.withdrawAllCollateral(order.subAccountId);
                }
            }
        }

        emit FillOrder(orderId, orderType, orderData);
    }

    /**
     * @dev   Add/remove liquidity. called by Broker
     *
     *        Check _getLiquidityFeeRate in Liquidity.sol on how to calculate liquidity fee.
     * @param orderId           order id
     * @param assetPrice        token price that added/removed to
     * @param mlpPrice          mlp price
     * @param currentAssetValue liquidity USD value of a single asset in all chains (even if tokenId is a stable asset)
     * @param targetAssetValue  weight / Σ weight * total liquidity USD value in all chains
     */
    function fillLiquidityOrder(
        uint64 orderId,
        uint96 assetPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue
    ) external onlyBroker {
        require(_orders.contains(orderId), "OID"); // can not find this OrderID
        bytes32[3] memory orderData = _orders.get(orderId);
        _orders.remove(orderId);
        OrderType orderType = LibOrder.getOrderType(orderData);
        require(orderType == OrderType.LiquidityOrder, "TYP"); // order TYPe mismatch

        LiquidityOrder memory order = orderData.decodeLiquidityOrder();
        require(_blockTimestamp() >= order.placeOrderTime + liquidityLockPeriod, "LCK"); // mlp token is LoCKed
        uint96 amount = order.amount;
        if (order.isAdding) {
            IERC20Upgradeable collateral = IERC20Upgradeable(_pool.getAssetAddress(order.assetId));
            collateral.safeTransfer(address(_pool), amount);
            _pool.addLiquidity(
                order.account,
                order.assetId,
                amount,
                assetPrice,
                mlpPrice,
                currentAssetValue,
                targetAssetValue
            );
        } else {
            _mlp.safeTransfer(address(_pool), amount);
            _pool.removeLiquidity(
                order.account,
                amount,
                order.assetId,
                assetPrice,
                mlpPrice,
                currentAssetValue,
                targetAssetValue
            );
        }

        emit FillOrder(orderId, orderType, orderData);
    }

    /**
     * @dev   Withdraw collateral/profit. called by Broker
     *
     * @param orderId           order id
     * @param collateralPrice   collateral price. decimals = 18
     * @param assetPrice        asset price. decimals = 18
     * @param profitAssetPrice  profit asset price. decimals = 18
     */
    function fillWithdrawalOrder(
        uint64 orderId,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external onlyBroker {
        require(_orders.contains(orderId), "OID"); // can not find this OrderID
        bytes32[3] memory orderData = _orders.get(orderId);
        _orders.remove(orderId);
        OrderType orderType = LibOrder.getOrderType(orderData);
        require(orderType == OrderType.WithdrawalOrder, "TYP"); // order TYPe mismatch

        WithdrawalOrder memory order = orderData.decodeWithdrawalOrder();
        if (order.isProfit) {
            _pool.withdrawProfit(
                order.subAccountId,
                order.amount,
                order.profitTokenId,
                collateralPrice,
                assetPrice,
                profitAssetPrice
            );
        } else {
            _pool.withdrawCollateral(order.subAccountId, order.amount, collateralPrice, assetPrice);
        }

        emit FillOrder(orderId, orderType, orderData);
    }

    /**
     * @notice Cancel an order
     */
    function cancelOrder(uint64 orderId) external {
        require(_orders.contains(orderId), "OID"); // can not find this OrderID
        bytes32[3] memory orderData = _orders.get(orderId);
        _orders.remove(orderId);
        address account = orderData.getOrderOwner();
        require(msg.sender == account, "SND"); // SeNDer is not authorized

        OrderType orderType = LibOrder.getOrderType(orderData);
        if (orderType == OrderType.PositionOrder) {
            PositionOrder memory order = orderData.decodePositionOrder();
            if (order.isIncreasing() && order.collateral > 0) {
                address collateralAddress = _pool.getAssetAddress(order.subAccountId.getSubAccountCollateralId());
                _transferOut(collateralAddress, account, order.collateral);
            }
        } else if (orderType == OrderType.LiquidityOrder) {
            LiquidityOrder memory order = orderData.decodeLiquidityOrder();
            if (order.isAdding) {
                address collateralAddress = _pool.getAssetAddress(order.assetId);
                _transferOut(collateralAddress, account, order.amount);
            } else {
                _mlp.safeTransfer(account, order.amount);
            }
        }
        emit CancelOrder(orderId, LibOrder.getOrderType(orderData), orderData);
    }

    /**
     * @notice Trader can withdraw all collateral only when position = 0
     */
    function withdrawAllCollateral(bytes32 subAccountId) external {
        LibSubAccount.DecodedSubAccountId memory account = subAccountId.decodeSubAccountId();
        require(account.account == msg.sender, "SND"); // SeNDer is not authorized
        _pool.withdrawAllCollateral(subAccountId);
    }

    /**
     * @notice Broker can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     *         Check _getFundingRate in Liquidity.sol on how to calculate funding rate.
     * @param  stableUtilization    Stable coin utilization in all chains
     * @param  unstableTokenIds     All unstable Asset id(s) MUST be passed in order. ex: 1, 2, 5, 6, ...
     * @param  unstableUtilizations Unstable Asset utilizations in all chains
     * @param  unstablePrices       Unstable Asset prices
     */
    function updateFundingState(
        uint32 stableUtilization, // 1e5
        uint8[] calldata unstableTokenIds,
        uint32[] calldata unstableUtilizations, // 1e5
        uint96[] calldata unstablePrices
    ) external onlyBroker {
        _pool.updateFundingState(stableUtilization, unstableTokenIds, unstableUtilizations, unstablePrices);
    }

    /**
     * @notice Deposit collateral into a subAccount
     */
    function depositCollateral(bytes32 subAccountId, uint256 collateralAmount) external payable {
        LibSubAccount.DecodedSubAccountId memory account = subAccountId.decodeSubAccountId();
        require(account.account == msg.sender, "SND"); // SeNDer is not authorized
        require(collateralAmount != 0, "C=0"); // Collateral Is Zero
        address collateralAddress = _pool.getAssetAddress(account.collateralId);
        _transferIn(collateralAddress, address(_pool), collateralAmount);
        _pool.depositCollateral(subAccountId, collateralAmount);
    }

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external onlyBroker {
        _pool.liquidate(subAccountId, profitAssetId, collateralPrice, assetPrice, profitAssetPrice);
        // auto withdraw
        (uint96 collateral, uint96 size, , , ) = _pool.getSubAccount(subAccountId);
        if (collateral > 0) {
            _pool.withdrawAllCollateral(subAccountId);
        }
    }

    function redeemMuxToken(uint8 tokenId, uint96 muxTokenAmount) external {
        Asset memory asset = _pool.getAssetInfo(tokenId);
        _transferIn(asset.muxTokenAddress, address(_pool), muxTokenAmount);
        _pool.redeemMuxToken(msg.sender, tokenId, muxTokenAmount);
    }

    function _transferIn(
        address tokenAddress,
        address recipient,
        uint256 rawAmount
    ) private {
        if (tokenAddress == address(_weth)) {
            require(msg.value > 0 && msg.value == rawAmount, "VAL"); // transaction VALue SHOULD equal to rawAmount
            _weth.deposit{ value: rawAmount }();
            if (recipient != address(this)) {
                _weth.transfer(recipient, rawAmount);
            }
        } else {
            IERC20Upgradeable(tokenAddress).safeTransferFrom(msg.sender, recipient, rawAmount);
        }
    }

    function _transferOut(
        address tokenAddress,
        address recipient,
        uint256 rawAmount
    ) internal {
        if (tokenAddress == address(_weth)) {
            _weth.transfer(address(_nativeUnwrapper), rawAmount);
            INativeUnwrapper(_nativeUnwrapper).unwrap(payable(recipient), rawAmount);
        } else {
            IERC20Upgradeable(tokenAddress).safeTransfer(recipient, rawAmount);
        }
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }
}
