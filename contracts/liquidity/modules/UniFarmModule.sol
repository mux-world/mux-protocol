// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Module.sol";

import "hardhat/console.sol";

contract UniFarmModule is Module {
    using Address for address;
    using SafeERC20 for IERC20;

    uint256 public constant K_INDEX = 0;

    address public immutable router;
    address public immutable pair;
    address public immutable tokenA;
    address public immutable tokenB;
    uint256 public immutable poolId;
    address public immutable stake;

    constructor(
        address router_,
        address pair_,
        address tokenA_,
        address tokenB_,
        uint256 poolId_,
        address stake_
    ) {
        router = router_;
        pair = pair_;
        tokenA = tokenA_;
        tokenB = tokenB_;
        poolId = poolId_;
        stake = stake_;
    }

    function id() public pure override returns (bytes32) {
        return LibUtils.toBytes32("pc-demo-farm-mod");
    }

    function meta()
        public
        pure
        override
        returns (
            bytes32[] memory ids,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        )
    {
        ids = new bytes32[](5);
        ids[0] = LibUtils.toBytes32("getLpBalance");
        ids[1] = LibUtils.toBytes32("getFees");
        ids[2] = LibUtils.toBytes32("getSpotAmounts");
        ids[3] = LibUtils.toBytes32("addLiquidity");
        ids[4] = LibUtils.toBytes32("removeLiquidity");
        selectors = new bytes4[](5);
        selectors[0] = this.getLpBalance.selector;
        selectors[1] = this.getFees.selector;
        selectors[2] = this.getSpotAmounts.selector;
        selectors[3] = this.addLiquidity.selector;
        selectors[4] = this.removeLiquidity.selector;
        initialStates = new bytes32[](1);
    }

    function getLpBalance() public view returns (uint256) {
        (bool hasFee, uint256[] memory feeAmounts) = _getFees();
        uint256 shareAmount = hasFee ? _getRedeemingShareAmount(feeAmounts[0], feeAmounts[1]) : 0;
        return _getLpBalance() - shareAmount;
    }

    function getFees() public view returns (uint256[] memory feeAmounts) {
        (, feeAmounts) = _getFees();
    }

    function getSpotAmounts(uint256 shareAmount) public view returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        if (shareAmount != 0) {
            uint256 totalSupply = IERC20(pair).totalSupply();
            (amounts[0], amounts[1]) = _getSpotAmounts(shareAmount, totalSupply);
        }
    }

    function addLiquidity(
        uint256[] memory maxAmounts,
        uint256[] memory minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(maxAmounts.length == 2, "L!2");
        require(maxAmounts.length == minAmounts.length, "L!L");
        // fee
        {
            (bool hasFee, uint256[] memory feeAmounts) = _getFees();
            if (hasFee) {
                require(_vault != address(0), "ZVD"); // zero vault address
                uint256 shareAmount = _getRedeemingShareAmount(feeAmounts[0], feeAmounts[1]);
                IERC20(pair).approve(router, shareAmount);
                (feeAmounts[0], feeAmounts[1]) = IUniswapV2Router(router).removeLiquidity(
                    tokenA,
                    tokenB,
                    shareAmount,
                    feeAmounts[0],
                    feeAmounts[1],
                    address(this),
                    deadline
                );

                IERC20(tokenA).safeTransfer(_vault, feeAmounts[0]);
                IERC20(tokenB).safeTransfer(_vault, feeAmounts[1]);
            }
        }
        // approve
        IERC20(tokenA).approve(router, maxAmounts[0]);
        IERC20(tokenB).approve(router, maxAmounts[1]);
        // add liquidity
        addedAmounts = new uint256[](2);
        (addedAmounts[0], addedAmounts[1], liquidityAmount) = IUniswapV2Router(router).addLiquidity(
            tokenA,
            tokenB,
            maxAmounts[0],
            maxAmounts[1],
            minAmounts[0],
            minAmounts[1],
            address(this),
            deadline
        );
        // stake
        if (stake != address(0)) {
            IERC20(pair).approve(stake, liquidityAmount);
            IStake(stake).deposit(poolId, liquidityAmount);
        }
        // update k
        uint256[] memory amounts = getSpotAmounts(_getLpBalance());
        _writeState(K_INDEX, bytes32(amounts[0] * amounts[1]));
    }

    function removeLiquidity(
        uint256 shareAmount,
        uint256[] memory minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory removedAmounts) {
        require(minAmounts.length == 2, "L!2");
        // fee
        (bool hasFee, uint256[] memory feeAmounts) = _getFees();
        uint256 feeShareAmount = _getRedeemingShareAmount(feeAmounts[0], feeAmounts[1]);
        // stake
        if (stake != address(0)) {
            IStake(stake).withdraw(poolId, shareAmount + feeShareAmount);
        }
        IERC20(pair).approve(router, shareAmount + feeShareAmount);
        removedAmounts = new uint256[](2);
        (removedAmounts[0], removedAmounts[1]) = IUniswapV2Router(router).removeLiquidity(
            tokenA,
            tokenB,
            shareAmount + feeShareAmount,
            minAmounts[0],
            minAmounts[1],
            address(this),
            deadline
        );
        if (hasFee) {
            require(_vault != address(0), "ZVD"); // zero vault address
            IERC20(tokenA).safeTransfer(_vault, feeAmounts[0]);
            IERC20(tokenB).safeTransfer(_vault, feeAmounts[1]);
        }
        // update k
        uint256[] memory amounts = getSpotAmounts(_getLpBalance());
        _writeState(K_INDEX, bytes32(amounts[0] * amounts[1]));
    }

    function _getFees() internal view returns (bool hasFee, uint256[] memory feeAmounts) {
        // x = reserveA * shareAmount / shareTotalSupply - _sqrt(k1 * reserveA / reserveB)
        // y = reserveB / reserveA * x
        feeAmounts = new uint256[](2);
        uint256 shareAmount = _getLpBalance();
        if (shareAmount != 0) {
            IERC20 shareToken = IERC20(pair);
            hasFee = true;
            uint256 shareTotalSupply = shareToken.totalSupply();
            uint256 k = uint256(_readState(0));
            (uint256 reserveA, uint256 reserveB) = _getReserves();
            feeAmounts[0] = (reserveA * shareAmount) / shareTotalSupply - _sqrt((k / reserveB) * reserveA);
            feeAmounts[1] = (reserveB / reserveA) * feeAmounts[0];
        }
    }

    function _getLpBalance() internal view returns (uint256 shareAmount) {
        if (stake == address(0)) {
            return IERC20(pair).balanceOf(address(this));
        } else {
            return IStake(stake).userInfo(poolId, address(this)).amount;
        }
    }

    function _getSpotAmounts(uint256 shareAmount, uint256 totalSupply)
        internal
        view
        returns (uint256 amountA, uint256 amountB)
    {
        uint256 balance0 = IERC20(tokenA).balanceOf(pair);
        uint256 balance1 = IERC20(tokenB).balanceOf(pair);
        amountA = (shareAmount * balance0) / totalSupply;
        amountB = (shareAmount * balance1) / totalSupply;
    }

    function _getRedeemingShareAmount(uint256 amountA, uint256 amountB) internal view returns (uint256 shareAmount) {
        uint256 balance0 = IERC20(tokenA).balanceOf(pair);
        uint256 balance1 = IERC20(tokenB).balanceOf(pair);
        uint256 totalSupply = IERC20(pair).totalSupply();
        uint256 shareAmountA = (amountA * totalSupply) / balance0;
        uint256 shareAmountB = (amountB * totalSupply) / balance1;
        shareAmount = shareAmountA >= shareAmountB ? shareAmountA : shareAmountB;
    }

    function _addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB) = _getReserves();
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

    function _getReserves() internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = _sortTokens();
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _sortTokens() internal view returns (address token0, address token1) {
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
    struct UserInfo {
        uint256 amount; // LP tokens provided
        uint256 rewardDebt; // pending reward = user.amount * pool.accRewardPerShare - user.rewardDebt
    }

    function userInfo(uint256, address) external view returns (UserInfo memory);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;
}
