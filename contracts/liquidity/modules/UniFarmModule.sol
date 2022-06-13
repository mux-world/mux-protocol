// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Module.sol";

/**
 * @notice A module to provide liquidity to uniswap-v2-like dex then farm on some project with the lpToken.
 */
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
        return LibUtils.toBytes32("uni-like-farm-mod");
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
        return _getLpBalance() - _getFeeShareAmount();
    }

    function getFees() public view returns (uint256[] memory feeAmounts) {
        uint256 feeShareAmount = _getFeeShareAmount();
        return getSpotAmounts(feeShareAmount);
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
        uint256 feeShareAmount = _getFeeShareAmount();
        if (feeShareAmount > 0 && _vault != address(0)) {
            IERC20(pair).approve(router, feeShareAmount);
            (uint256 feeAmount0, uint256 feeAmount1) = IUniswapV2Router(router).removeLiquidity(
                tokenA,
                tokenB,
                feeShareAmount,
                0,
                0,
                address(this),
                deadline
            );
            IERC20(tokenA).safeTransfer(_vault, feeAmount0);
            IERC20(tokenB).safeTransfer(_vault, feeAmount1);
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
        _updateK();
    }

    function removeLiquidity(
        uint256 shareAmount,
        uint256[] memory minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory removedAmounts) {
        require(minAmounts.length == 2, "L!2");
        // fee
        uint256 feeShareAmount = _getFeeShareAmount();
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
        uint256 feeRate = (feeShareAmount * 1e18) / (shareAmount + feeShareAmount);
        uint256 feeAmount0 = (removedAmounts[0] * feeRate) / 1e18;
        uint256 feeAmount1 = (removedAmounts[1] * feeRate) / 1e18;
        if (feeShareAmount > 0) {
            require(_vault != address(0), "ZVD"); // zero vault address
            IERC20(tokenA).safeTransfer(_vault, feeAmount0);
            IERC20(tokenB).safeTransfer(_vault, feeAmount1);
        }
        removedAmounts[0] -= feeAmount0;
        removedAmounts[1] -= feeAmount1;
        _updateK();
    }

    function _updateK() internal {
        uint256[] memory amounts = getSpotAmounts(_getLpBalance());
        _writeState(K_INDEX, bytes32(amounts[0] * amounts[1]));
    }

    function _getFeeShareAmount() internal view returns (uint256) {
        uint256 shareAmount = _getLpBalance();
        if (shareAmount == 0) {
            return 0;
        }
        uint256 poolShareAmount = IERC20(pair).totalSupply();
        (uint256 reserveA, uint256 reserveB) = _getReserves();
        uint256 k = uint256(_readState(K_INDEX));
        return shareAmount - (_sqrt(k) * poolShareAmount) / _sqrt(reserveA * reserveB);
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
        (uint256 reserveA, uint256 reserveB) = _getReserves();
        amountA = (shareAmount * reserveA) / totalSupply;
        amountB = (shareAmount * reserveB) / totalSupply;
    }

    function _getReserves() internal view returns (uint256 reserveA, uint256 reserveB) {
        // (address token0, ) = _sortTokens();
        // (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        // (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        reserveA = IERC20(tokenA).balanceOf(pair);
        reserveB = IERC20(tokenB).balanceOf(pair);
    }

    // function _sortTokens() internal view returns (address token0, address token1) {
    //     require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
    //     (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    //     require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    // }

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
    function kLast() external view returns (uint256);

    // function getReserves()
    //     external
    //     view
    //     returns (
    //         uint112 _reserve0,
    //         uint112 _reserve1,
    //         uint32 _blockTimestampLast
    //     );
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
