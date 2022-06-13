// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "../../interfaces/ILiquidityPool.sol";
import "../../interfaces/ILiquidityManager.sol";
import "../../interfaces/IDexLiquidityModule.sol";
import "./DexModule.sol";

/**
 * @notice A module to provide liquidity to uniswap-v2-like dex then farm on some project with the lpToken.
 */
contract UniFarmModule is DexModule, IDexLiquidityModule {
    using Address for address;
    using SafeERC20 for IERC20;

    uint256 public constant K_INDEX = 0;
    uint256 public constant FEE0_INDEX = 1;
    uint256 public constant FEE1_INDEX = 2;

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
        address token0 = IUniswapV2Pair(pair_).token0();
        address token1 = IUniswapV2Pair(pair_).token1();
        require((tokenA_ == token0 && tokenB_ == token1) || (tokenA_ == token1 && tokenB_ == token0), "TKA");
        tokenA = tokenA_;
        tokenB = tokenB_;
        router = router_;
        pair = pair_;
        poolId = poolId_;
        stake = stake_;
    }

    function id() public pure override returns (bytes32) {
        return LibUtils.toBytes32("uni-like-farm-mod");
    }

    function meta()
        public
        view
        override
        returns (
            bytes32[] memory methodIds,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        )
    {
        methodIds = new bytes32[](7);
        methodIds[0] = LibUtils.toBytes32("getLpBalance");
        methodIds[1] = LibUtils.toBytes32("getFees");
        methodIds[2] = LibUtils.toBytes32("getSpotAmounts");
        methodIds[3] = LibUtils.toBytes32("addLiquidity");
        methodIds[4] = LibUtils.toBytes32("removeLiquidity");
        methodIds[5] = LibUtils.toBytes32("getValidationData");
        methodIds[6] = LibUtils.toBytes32("getAmountOut");
        selectors = new bytes4[](7);
        selectors[0] = this.getLpBalance.selector;
        selectors[1] = this.getFees.selector;
        selectors[2] = this.getSpotAmounts.selector;
        selectors[3] = this.addLiquidity.selector;
        selectors[4] = this.removeLiquidity.selector;
        selectors[5] = this.getValidationData.selector;
        selectors[6] = this.getAmountOut.selector;
        initialStates = new bytes32[](3);
    }

    function tokens() public view override returns (bool needCheck, address[] memory tokens_) {
        needCheck = true;
        tokens_ = new address[](2);
        tokens_[0] = tokenA;
        tokens_[1] = tokenB;
    }

    function getLpBalance() public view override returns (uint256) {
        return _getLpBalance() - _getFeeShareAmount();
    }

    function getFees()
        public
        view
        override
        returns (
            address[] memory rewardTokens,
            uint256[] memory collectedFeeAmounts,
            uint256[] memory pendingFeeAmounts
        )
    {
        (, rewardTokens) = tokens();
        uint256 feeShareAmount = _getFeeShareAmount();
        pendingFeeAmounts = getSpotAmounts(feeShareAmount);
        collectedFeeAmounts = new uint256[](2);
        collectedFeeAmounts[0] = uint256(_readState(FEE0_INDEX));
        collectedFeeAmounts[1] = uint256(_readState(FEE1_INDEX));
    }

    function getValidationData(uint256[] memory minAmounts) public view override returns (bytes memory data) {
        require(minAmounts.length == 2, "L!2");
        return abi.encode(minAmounts[0], minAmounts[1]);
    }

    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view override returns (uint256 amountOut) {
        require(tokenIn == tokenA || tokenIn == tokenB, "Unknown in token");
        require(tokenOut == tokenA || tokenOut == tokenB, "Unknown out token");
        require(amountIn > 0, "Zero amount in");

        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = tokenIn == tokenA ? (reserve0, reserve1) : (reserve1, reserve0);
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee / reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getSpotAmounts(uint256 shareAmount) public view override returns (uint256[] memory amounts) {
        if (shareAmount != 0) {
            uint256 totalSupply = IERC20(pair).totalSupply();
            amounts = _getSpotAmounts(shareAmount, totalSupply);
        } else {
            amounts = new uint256[](2);
        }
    }

    function addLiquidity(
        uint256[] calldata maxAmounts,
        uint256 deadline,
        bytes memory validationData
    ) public override returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(maxAmounts.length == 2, "L!2");
        // fee
        uint256 feeShareAmount = _getFeeShareAmount();
        if (feeShareAmount > 0 && _vault != address(0)) {
            IERC20(pair).approve(router, feeShareAmount);
            try
                IUniswapV2Router(router).removeLiquidity(tokenA, tokenB, feeShareAmount, 0, 0, address(this), deadline)
            returns (uint256 feeAmount0, uint256 feeAmount1) {
                _transferFee(feeAmount0, feeAmount1);
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("Withdraw dex fee failed");
            }
        }
        // approve
        IERC20(tokenA).approve(router, maxAmounts[0]);
        IERC20(tokenB).approve(router, maxAmounts[1]);
        // add liquidity
        addedAmounts = new uint256[](2);
        uint256[2] memory minAmounts;
        if (validationData.length > 0) {
            require(validationData.length >= 64, "IDL");
            (minAmounts[0], minAmounts[1]) = abi.decode(validationData, (uint256, uint256));
        }

        try
            IUniswapV2Router(router).addLiquidity(
                tokenA,
                tokenB,
                maxAmounts[0],
                maxAmounts[1],
                minAmounts[0],
                minAmounts[1],
                address(this),
                deadline
            )
        returns (uint256 amount0_, uint256 amount1_, uint256 liquidityAmount_) {
            (addedAmounts[0], addedAmounts[1], liquidityAmount) = (amount0_, amount1_, liquidityAmount_);
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("Fail to remove liquidity");
        }
        // stake
        if (stake != address(0)) {
            IERC20(pair).approve(stake, liquidityAmount);
            try IStake(stake).deposit(poolId, liquidityAmount) {} catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("Fail to stake share");
            }
        }
        _updateK();
    }

    function removeLiquidity(
        uint256 shareAmount,
        uint256[] memory minAmounts,
        uint256 deadline
    ) public override returns (uint256[] memory removedAmounts) {
        require(minAmounts.length == 2, "L!2");
        // fee
        uint256 feeShareAmount = _getFeeShareAmount();
        // stake
        if (stake != address(0)) {
            try IStake(stake).withdraw(poolId, shareAmount + feeShareAmount) {} catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("Fail to stake share");
            }
        }
        IERC20(pair).approve(router, shareAmount + feeShareAmount);
        removedAmounts = new uint256[](2);
        try
            IUniswapV2Router(router).removeLiquidity(
                tokenA,
                tokenB,
                shareAmount + feeShareAmount,
                minAmounts[0],
                minAmounts[1],
                address(this),
                deadline
            )
        returns (uint256 amount0_, uint256 amount1_) {
            (removedAmounts[0], removedAmounts[1]) = (amount0_, amount1_);
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("Fail to stake share");
        }
        uint256 feeRate = (feeShareAmount * 1e18) / (shareAmount + feeShareAmount);
        uint256 feeAmount0 = (removedAmounts[0] * feeRate) / 1e18;
        uint256 feeAmount1 = (removedAmounts[1] * feeRate) / 1e18;
        if (feeShareAmount > 0) {
            _transferFee(feeAmount0, feeAmount1);
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
        uint256[] memory reserves = _getReserves();
        uint256 k = uint256(_readState(K_INDEX));
        return shareAmount - (_sqrt(k) * poolShareAmount) / _sqrt(reserves[0] * reserves[1]);
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
        returns (uint256[] memory amounts)
    {
        amounts = _getReserves();
        amounts[0] = (shareAmount * amounts[0]) / totalSupply;
        amounts[1] = (shareAmount * amounts[1]) / totalSupply;
    }

    function _getReserves() internal view returns (uint256[] memory reserves) {
        reserves = new uint256[](2);
        reserves[0] = IERC20(tokenA).balanceOf(pair);
        reserves[1] = IERC20(tokenB).balanceOf(pair);
    }

    function _transferFee(uint256 feeAmount0, uint256 feeAmount1) internal {
        _transferFee(tokenA, feeAmount0);
        _transferFee(tokenB, feeAmount1);
        _writeState(FEE0_INDEX, bytes32(uint256(_readState(FEE0_INDEX)) + feeAmount0));
        _writeState(FEE1_INDEX, bytes32(uint256(_readState(FEE1_INDEX)) + feeAmount1));
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
    function token0() external view returns (address);

    function token1() external view returns (address);

    function kLast() external view returns (uint256);

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
