// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../interfaces/IConnector.sol";


interface IUniswapV2Router {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

interface IUniswapV2Pair {
    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );
}

interface IStake {
    function stake(uint256 amount) external;
}

contract UniV2Connector is IConnector {
    using Address for address;

    struct DexContext {
        address router;
        address pair;
        address tokenA;
        address tokenB;
        address stake;
        uint256 k;
    }

    function name() public view override returns (string memory) {
        return "UniV2Connector";
    }

    function validate(bytes memory context) public view override {
        DexContext memory dexContext = _getDexContext(context);
        require(dexContext.router.isContract(), "R!C");
        require(dexContext.pair.isContract(), "P!C");
        require(dexContext.tokenA.isContract(), "TkA");
        require(dexContext.tokenB.isContract(), "TkB");
        // more validate for uni
    }

    function getLpBalance(bytes memory context) public override returns (uint256) {
        DexContext memory dexContext = _getDexContext(context);
        return IERC20(dexContext.pair).balanceOf(address(this));
    }

    function getDexRewards(bytes memory context)
        public
        override
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {}

    function claimDexRewards(bytes memory dexContext)
        external
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {}

    function getDexFees(bytes memory context) public returns (uint256[] memory feeAmounts) {
        DexContext memory dexContext = _getDexContext(context);
        (, feeAmounts) = _getFee(dexContext);
    }

    function _getFee(DexContext memory dexContext) internal returns (bool hasFee, uint256[] memory feeAmounts) {
        // x = reserveB * shareAmount / shareTotalSupply - _sqrt(k * reserveB / reserveA)
        // y = reserveB / reserveA * x
        IERC20 shareToken = IERC20(dexContext.pair);
        feeAmounts = new uint256[](2);
        uint256 shareAmount = shareToken.balanceOf(address(this));
        if (shareAmount != 0) {
            uint256 shareTotalSupply = shareToken.totalSupply();
            (uint256 amountA, uint256 amountB) = _calcRedeemableAmounts(dexContext, shareAmount, shareTotalSupply);
            uint256 currentK = amountA * amountB;
            (uint256 reserveA, uint256 reserveB) = _getReserves(dexContext.pair, dexContext.tokenA, dexContext.tokenB);
            feeAmounts[0] = (reserveB * shareAmount) / shareTotalSupply - _sqrt((currentK * reserveB) / reserveA);
            feeAmounts[1] = (reserveB / reserveA) * feeAmounts[0];
        }
    }

    function getDexRedeemableAmounts(bytes memory context, uint256 shareAmount)
        public
        override
        returns (uint256[] memory amounts)
    {
        DexContext memory dexContext = _getDexContext(context);
        amounts = new uint256[](2);
        uint256 totalSupply = IERC20(dexContext.pair).totalSupply();
        (amounts[0], amounts[1]) = _calcRedeemableAmounts(dexContext, shareAmount, totalSupply);
    }

    function _calcRedeemableAmounts(
        DexContext memory dexContext,
        uint256 shareAmount,
        uint256 totalSupply
    ) internal returns (uint256 amountA, uint256 amountB) {
        uint256 balance0 = IERC20(dexContext.tokenA).balanceOf(dexContext.router);
        uint256 balance1 = IERC20(dexContext.tokenB).balanceOf(dexContext.router);
        amountA = (shareAmount * balance0) / totalSupply;
        amountB = (shareAmount * balance1) / totalSupply;
    }

    function _calcRedeemingShare(
        DexContext memory dexContext,
        uint256 amountA,
        uint256 amountB
    ) internal returns (uint256 shareAmount) {
        uint256 balance0 = IERC20(dexContext.tokenA).balanceOf(dexContext.router);
        uint256 balance1 = IERC20(dexContext.tokenB).balanceOf(dexContext.router);
        uint256 totalSupply = IERC20(dexContext.pair).totalSupply();
        uint256 shareAmountA = (amountA * totalSupply) / balance0;
        uint256 shareAmountB = (amountB * totalSupply) / balance1;
        shareAmount = shareAmountA >= shareAmountB ? shareAmountA : shareAmountB;
    }

    function addDexLiquidity(
        bytes memory context,
        uint256[] memory maxAmounts,
        uint256[] memory minAmounts,
        uint256 deadline
    )
        public
        override
        returns (
            bytes memory newDexContext,
            uint256[] memory addedAmounts,
            uint256 liquidityAmount,
            uint256[] memory feeAmounts
        )
    {
        require(maxAmounts.length == 2, "L!2");
        require(maxAmounts.length == minAmounts.length, "L!L");
        DexContext memory dexContext = _getDexContext(context);
        // fee
        {
            bool hasFee;
            (hasFee, feeAmounts) = _getFee(dexContext);
            if (hasFee) {
                uint256 shareAmount = _calcRedeemingShare(dexContext, feeAmounts[0], feeAmounts[1]);
                (feeAmounts[0], feeAmounts[1]) = IUniswapV2Router(dexContext.router).removeLiquidity(
                    dexContext.tokenA,
                    dexContext.tokenB,
                    shareAmount,
                    feeAmounts[0],
                    feeAmounts[1],
                    address(this),
                    deadline
                );
            }
        }
        // approve
        IERC20(dexContext.tokenA).approve(dexContext.router, maxAmounts[0]);
        IERC20(dexContext.tokenB).approve(dexContext.router, maxAmounts[1]);
        // add liquidity
        addedAmounts = new uint256[](2);
        (addedAmounts[0], addedAmounts[1], liquidityAmount) = IUniswapV2Router(dexContext.router).addLiquidity(
            dexContext.tokenA,
            dexContext.tokenB,
            maxAmounts[0],
            maxAmounts[1],
            minAmounts[0],
            minAmounts[1],
            address(this),
            deadline
        );
        newDexContext = _writeContext(dexContext);
        // stake
        if (dexContext.stake != address(0)) {
            IERC20(dexContext.pair).approve(dexContext.stake, liquidityAmount);
            IStake(dexContext.stake).stake(liquidityAmount);
        }
    }

    function removeDexLiquidity(
        bytes memory context,
        uint256 shareAmount,
        uint256[] memory minAmounts,
        uint256 deadline
    )
        public
        override
        returns (
            bytes memory newDexContext,
            uint256[] memory removedAmounts,
            uint256[] memory feeAmounts
        )
    {
        require(minAmounts.length == 2, "L!2");
        DexContext memory dexContext = _getDexContext(context);
        // fee
        (, feeAmounts) = _getFee(dexContext);
        uint256 extraShareAmount = _calcRedeemingShare(dexContext, feeAmounts[0], feeAmounts[1]);

        IERC20(dexContext.pair).approve(dexContext.router, shareAmount);
        removedAmounts = new uint256[](2);
        (removedAmounts[0], removedAmounts[1]) = IUniswapV2Router(dexContext.router).removeLiquidity(
            dexContext.tokenA,
            dexContext.tokenB,
            shareAmount + extraShareAmount,
            minAmounts[0],
            minAmounts[1],
            address(this),
            deadline
        );
        newDexContext = _writeContext(dexContext);
        // handle fee
    }

    function _getDexContext(bytes memory context) internal pure returns (DexContext memory) {
        return abi.decode(context, (DexContext));
    }

    function _writeContext(DexContext memory dexContext) internal pure returns (bytes memory) {
        return abi.encode(dexContext);
    }

    function _addLiquidity(
        address pair,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB) = _getReserves(pair, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _getReserves(
        address pair,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = _sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function _quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
