// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IWETH9.sol";
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
    IWETH internal _weth;

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
        address weth
    ) external initializer {
        __SafeOwnable_init();

        _pool = ILiquidityPool(pool);
        _mlp = IERC20Upgradeable(mlp);
        _weth = IWETH(weth);
    }

    receive() external payable {
        require(msg.sender == address(_weth), "Rcv");
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

    function placePositionOrder(
        bytes32 subAccountId,
        uint96 collateralAmount,
        uint96 size,
        uint96 price,
        uint8 profitTokenId,
        uint8 flags
    ) external payable onlyNotPaused {
        // TODO: more validations
        LibSubAccount.DecodedSubAccountId memory account = subAccountId.decodeSubAccountId();
        require(account.account == msg.sender, "Snd");
        require(size != 0, "S=0");

        if (collateralAmount > 0 && (flags & LibOrder.POSITION_INCREASING != 0)) {
            address collateralAddress = _pool.getAssetAddress(account.collateralId);
            _transferIn(collateralAddress, address(this), collateralAmount);
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
    ) external payable onlyNotPaused {
        require(amount != 0, "A=0");
        address account = msg.sender;
        if (isAdding) {
            address collateralAddress = _pool.getAssetAddress(assetId);
            _transferIn(collateralAddress, address(this), amount);
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
        require(trader == msg.sender, "Snd");

        uint64 orderId = _nextOrderId++;
        bytes32[3] memory data = LibOrder.encodeWithdrawalOrder(orderId, subAccountId, amount, profitTokenId, isProfit);
        _orders.add(orderId, data);

        emit NewWithdrawalOrder(subAccountId, orderId, amount, profitTokenId, isProfit);
    }

    function fillPositionOrder(
        uint64 orderId,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external onlyBroker {
        require(_orders.contains(orderId), "Oid");
        bytes32[3] memory orderData = _orders.get(orderId);
        OrderType orderType = LibOrder.getOrderType(orderData);
        require(orderType == OrderType.PositionOrder, "Typ");

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
            require(isLimitPriceOk, "Lmt");
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
            _pool.closePosition(
                order.subAccountId,
                order.size,
                order.profitTokenId,
                collateralPrice,
                assetPrice,
                profitAssetPrice
            );

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
        uint96 mlpPrice,
        uint32 mlpFeeRate
    ) external onlyBroker {
        require(_orders.contains(orderId), "Oid");
        bytes32[3] memory orderData = _orders.get(orderId);
        OrderType orderType = LibOrder.getOrderType(orderData);
        require(orderType == OrderType.LiquidityOrder, "Typ");

        LiquidityOrder memory order = orderData.decodeLiquidityOrder();
        if (order.isAdding) {
            IERC20Upgradeable collateral = IERC20Upgradeable(_pool.getAssetAddress(order.assetId));
            collateral.safeTransfer(address(_pool), order.amount);
            _pool.addLiquidity(order.account, order.assetId, assetPrice, mlpPrice, mlpFeeRate);
        } else {
            _mlp.safeTransfer(address(_pool), order.amount);
            _pool.removeLiquidity(order.account, order.amount, order.assetId, assetPrice, mlpPrice, mlpFeeRate);
        }

        emit FillOrder(orderId, orderType, orderData);
        _orders.remove(orderId);
    }

    function fillWithdrawalOrder(
        uint64 orderId,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external onlyBroker {
        require(_orders.contains(orderId), "Oid");
        bytes32[3] memory orderData = _orders.get(orderId);
        OrderType orderType = LibOrder.getOrderType(orderData);
        require(orderType == OrderType.WithdrawalOrder, "Typ");

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
        _orders.remove(orderId);
    }

    function cancelOrder(uint64 orderId) external {
        require(_orders.contains(orderId), "Oid");
        bytes32[3] memory orderData = _orders.get(orderId);
        address account = orderData.getOrderOwner();
        require(msg.sender == account, "Typ");

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

    /**
     * @notice Broker can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     * @param  stableUtilization    Stable coin utilization
     * @param  unstableTokenIds     All unstable Asset id(s) MUST be passed in order. ex: 1, 2, 5, 6, ...
     * @param  unstableUtilizations Unstable Asset utilizations
     */
    function updateFundingState(
        uint32 stableUtilization, // 1e5
        uint8[] calldata unstableTokenIds,
        uint32[] calldata unstableUtilizations // 1e5
    ) external onlyBroker {
        _pool.updateFundingState(stableUtilization, unstableTokenIds, unstableUtilizations);
    }

    /**
     * @notice Deposit collateral into a subAccount
     */
    function depositCollateral(bytes32 subAccountId, uint256 collateralAmount) external payable {
        LibSubAccount.DecodedSubAccountId memory account = subAccountId.decodeSubAccountId();
        require(account.account == msg.sender, "Snd");
        require(collateralAmount != 0, "C=0");
        address collateralAddress = _pool.getAssetAddress(account.collateralId);
        _transferIn(collateralAddress, address(_pool), collateralAmount);
        _pool.depositCollateral(subAccountId);
    }

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId, // only used when !isLong
        uint96 collateralPrice,
        uint96 assetPrice,
        uint96 profitAssetPrice // only used when !isLong
    ) external onlyBroker {
        _pool.liquidate(subAccountId, profitAssetId, collateralPrice, assetPrice, profitAssetPrice);
    }

    function _transferIn(
        address tokenAddress,
        address recipient,
        uint256 rawAmount
    ) private {
        if (tokenAddress == address(_weth)) {
            require(msg.value > 0 && msg.value == rawAmount, "Val");
            _weth.deposit{ value: rawAmount }();
            if (recipient != address(this)) {
                _weth.transfer(recipient, rawAmount);
            }
        } else {
            IERC20Upgradeable(tokenAddress).safeTransferFrom(msg.sender, recipient, rawAmount);
        }
    }

    bytes32[50] _gap;
}
