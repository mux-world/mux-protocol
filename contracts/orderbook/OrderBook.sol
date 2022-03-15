// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/ILiquidityPool.sol";
import "../libraries/LibSubAccount.sol";
import "../libraries/LibOrder.sol";

import "./Types.sol";
import "./Admin.sol";

contract OrderBook is Initializable, Admin {
    using LibSubAccount for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibOrder for LibOrder.OrderList;
    using LibOrder for bytes32[3];
    using LibOrder for PositionOrder;
    using LibOrder for LiquidityOrder;
    using LibOrder for WithdrawalOrder;

    ILiquidityPool internal _pool;
    uint64 internal _nextOrderId;
    LibOrder.OrderList internal _orders;
    IERC20Upgradeable internal _mlp;

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

    function initialize(address pool, address mlp) external initializer {
        __SafeOwnable_init();

        _pool = ILiquidityPool(pool);
        _mlp = IERC20Upgradeable(mlp);
    }

    function getOrderCount() external view returns (uint256) {
        return _orders.length();
    }

    function getOrder(uint64 orderId) public view returns (bytes32[3] memory, bool) {
        return (_orders.get(orderId), _orders.contains(orderId));
    }

    function getOrders(uint256 begin, uint256 end)
        external
        view
        returns (bytes32[3][] memory orderArray, uint256 totalCount)
    {
        totalCount = _orders.length();
        if (begin <= end || begin >= totalCount) {
            return (orderArray, totalCount);
        }
        end = end <= totalCount ? end : totalCount + 1;
        uint256 size = end - begin;
        orderArray = new bytes32[3][](size);
        for (uint256 i = 0; i < size; i++) {
            orderArray[i] = _orders.at(i + begin);
        }
    }

    function placePositionOrder(
        bytes32 subAccountId,
        uint96 collateralAmount,
        uint96 size,
        uint96 price,
        uint8 profitTokenId,
        uint8 flags
    ) external onlyNotPaused {
        // TODO: more validations
        LibSubAccount.DecodedSubAccountId memory account = subAccountId.decodeSubAccountId();
        require(account.account == msg.sender, "UnauthorizedSubAccountId");
        require(size != 0, "ZeroSize");

        if (collateralAmount > 0 && (flags & LibOrder.POSITION_INCREASING != 0)) {
            IERC20Upgradeable collateral = IERC20Upgradeable(_pool.getAssetAddress(account.collateralId));
            collateral.safeTransferFrom(msg.sender, address(this), collateralAmount);
        }
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

        emit NewPositionOrder(subAccountId, orderId, collateralAmount, size, price, profitTokenId, flags);
    }

    function placeLiquidityOrder(
        uint8 assetId,
        uint96 amount,
        bool isAdding
    ) external onlyNotPaused {
        require(amount != 0, "ZeroAmount");
        address account = msg.sender;
        if (isAdding) {
            IERC20Upgradeable collateral = IERC20Upgradeable(_pool.getAssetAddress(assetId));
            collateral.safeTransferFrom(msg.sender, address(this), amount);
        } else {
            _mlp.safeTransferFrom(msg.sender, address(this), amount);
        }
        uint64 orderId = _nextOrderId++;
        bytes32[3] memory data = LibOrder.encodeLiquidityOrder(orderId, account, assetId, amount, isAdding);
        _orders.add(orderId, data);

        emit NewLiquidityOrder(account, orderId, assetId, amount, isAdding);
    }

    function placeWithdrawalOrder(
        bytes32 subAccountId,
        uint96 amount,
        uint8 profitTokenId,
        bool isProfit
    ) external onlyNotPaused {
        address trader = subAccountId.getSubAccountOwner();
        require(trader == msg.sender, "UnauthorizedSubAccountId");

        uint64 orderId = _nextOrderId++;
        bytes32[3] memory data = LibOrder.encodeWithdrawalOrder(orderId, subAccountId, amount, profitTokenId, isProfit);
        _orders.add(orderId, data);

        emit NewWithdrawalOrder(subAccountId, orderId, amount, profitTokenId, isProfit);
    }

    // TODO: support auto-wrap eth
    function fillPositionOrder(
        uint64 orderId,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external onlyBroker {
        require(_orders.contains(orderId), "OrderNotExists");
        bytes32[3] memory orderData = _orders.get(orderId);
        OrderType orderType = LibOrder.getOrderType(orderData);
        require(orderType == OrderType.PositionOrder, "NotPositionOrder");

        PositionOrder memory order = orderData.decodePositionOrder();
        if (!order.isMarketOrder()) {
            if (order.subAccountId.isLong()) {
                require(assetPrice <= order.price, "PriceTooHigh");
            } else {
                require(assetPrice >= order.price, "PriceTooLow");
            }
        }
        if (order.isIncreasing()) {
            // auto deposit
            if (order.collateral > 0) {
                IERC20Upgradeable collateral = IERC20Upgradeable(
                    _pool.getAssetAddress(order.subAccountId.getSubAccountCollateralId())
                );
                collateral.safeTransfer(address(_pool), order.collateral);
                _pool.depositCollateral(order.subAccountId);
            }
            _pool.openPosition(order.subAccountId, order.size, collateralPrice, assetPrice);
        } else {
            _pool.closePosition(order.subAccountId, order.size, collateralPrice, assetPrice, order.profitTokenId);
            // auto withdraw
            if (order.collateral > 0) {
                _pool.withdrawCollateral(order.subAccountId, order.collateral, collateralPrice, assetPrice);
            }
            if (order.isWithdrawIfEmpty()) {
                (uint96 collateral, uint96 size, , , ) = _pool.getSubAccount(order.subAccountId);
                if (size == 0 && collateral > 0) {
                    _pool.withdrawAllCollateral(order.subAccountId);
                }
            }
        }

        emit FillOrder(orderId, orderType, orderData);
        _orders.remove(orderId);
    }

    function fillLiquidityOrder(
        uint64 orderId,
        uint96 assetPrice,
        uint96 mlpPrice
    ) external onlyBroker {
        require(_orders.contains(orderId), "OrderNotExists");
        bytes32[3] memory orderData = _orders.get(orderId);
        OrderType orderType = LibOrder.getOrderType(orderData);
        require(orderType == OrderType.LiquidityOrder, "NotLiquidityOrder");

        LiquidityOrder memory order = orderData.decodeLiquidityOrder();
        if (order.isAdding) {
            IERC20Upgradeable collateral = IERC20Upgradeable(_pool.getAssetAddress(order.assetId));
            collateral.safeTransfer(address(_pool), order.amount);
            _pool.addLiquidity(order.account, order.assetId, assetPrice, mlpPrice);
        } else {
            _mlp.safeTransfer(address(_pool), order.amount);
            _pool.removeLiquidity(order.account, order.amount, order.assetId, assetPrice, mlpPrice);
        }

        emit FillOrder(orderId, orderType, orderData);
        _orders.remove(orderId);
    }

    function fillWithdrawalOrder(
        uint64 orderId,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external onlyBroker {
        require(_orders.contains(orderId), "OrderNotExists");
        bytes32[3] memory orderData = _orders.get(orderId);
        OrderType orderType = LibOrder.getOrderType(orderData);
        require(orderType == OrderType.WithdrawalOrder, "NotLiquidityOrder");

        WithdrawalOrder memory order = orderData.decodeWithdrawalOrder();
        if (order.isProfit) {
            _pool.withdrawProfit(order.subAccountId, order.amount, collateralPrice, assetPrice, order.profitTokenId);
        } else {
            _pool.withdrawCollateral(order.subAccountId, order.amount, collateralPrice, assetPrice);
        }

        emit FillOrder(orderId, orderType, orderData);
        _orders.remove(orderId);
    }

    // TODO: support auto-wrap eth ?
    function cancelOrder(uint64 orderId) external {
        require(_orders.contains(orderId), "OrderNotExists");
        bytes32[3] memory orderData = _orders.get(orderId);
        address account = orderData.getOrderOwner();
        require(msg.sender == account, "OrderOwnerNotMatch");

        OrderType orderType = LibOrder.getOrderType(orderData);
        if (orderType == OrderType.PositionOrder) {
            PositionOrder memory order = orderData.decodePositionOrder();
            if (order.isIncreasing() && order.collateral > 0) {
                IERC20Upgradeable collateral = IERC20Upgradeable(
                    _pool.getAssetAddress(order.subAccountId.getSubAccountCollateralId())
                );
                collateral.safeTransfer(account, order.collateral);
            }
        } else if (orderType == OrderType.LiquidityOrder) {
            LiquidityOrder memory order = orderData.decodeLiquidityOrder();
            if (order.isAdding) {
                IERC20Upgradeable collateral = IERC20Upgradeable(_pool.getAssetAddress(order.assetId));
                collateral.safeTransfer(account, order.amount);
            } else {
                _mlp.safeTransfer(account, order.amount);
            }
        }
        _orders.remove(orderId);
        emit CancelOrder(orderId, LibOrder.getOrderType(orderData), orderData);
    }

    function updateFundingState(
        uint8[] calldata tokenIds,
        uint32[] calldata fundingRates // 1e5
    ) external onlyBroker {
        _pool.updateFundingState(tokenIds, fundingRates);
    }

    /**
     * @notice Forward trader's collateral into pool.subAccount
     */
    // TODO: support auto-wrap eth
    function depositCollateral(bytes32 subAccountId, uint256 collateralAmount) external {
        LibSubAccount.DecodedSubAccountId memory account = subAccountId.decodeSubAccountId();
        require(account.account == msg.sender, "UnauthorizedSubAccountId");
        require(collateralAmount != 0, "ZeroAmount");

        IERC20Upgradeable collateral = IERC20Upgradeable(_pool.getAssetAddress(account.collateralId));
        collateral.safeTransferFrom(msg.sender, address(_pool), collateralAmount);
        _pool.depositCollateral(subAccountId);
    }
}
