// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../libraries/LibUtils.sol";
import "./DexAdapter.sol";

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

interface IFarm {
    struct UserInfo {
        uint256 amount; // LP tokens provided
        uint256 rewardDebt; // pending reward = user.amount * pool.accRewardPerShare - user.rewardDebt
    }

    function rewardToken() external view returns (address);

    function userInfo(uint256, address) external view returns (UserInfo memory);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function pendingReward(uint256 pid, address userAddress) external view returns (uint256);
}

contract SushiFarm is DexAdapter {
    using SafeERC20 for IERC20;

    struct Context {
        address router;
        address pair;
        uint256 poolId;
        address farm;
    }

    bytes32 constant LAST_K = keccak256("LAST_K");
    bytes32 constant CLAIMED_FARM_REWARD = keccak256("CLAIMED_FARM_REWARD");
    bytes32 constant CLAIMED_FEE0 = keccak256("CLAIMED_FEE0");
    bytes32 constant CLAIMED_FEE1 = keccak256("CLAIMED_FEE1");
    bytes32 constant RESERVED_FEE_LP_BALANCE = keccak256("RESERVED_FEE_LP_BALANCE");

    function initializeAdapter(bytes memory initialData) external override {
        Context memory context = abi.decode(initialData, (Context));
        require(context.router != address(0), "!A0");
        require(context.pair != address(0), "!A1");
        _dexData[_dexId()].config = initialData;
    }

    function getLpBalance() external view override returns (uint256 lpBalance) {
        lpBalance = _getNetLpBalance(_getContext());
    }

    function getFees()
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory claimedAmounts,
            uint256[] memory pendingAmounts
        )
    {
        Context memory context = _getContext();
        uint256 n = context.farm == address(0) ? 2 : 3;

        tokens = new address[](n);
        claimedAmounts = new uint256[](n);
        pendingAmounts = new uint256[](n);

        address[] memory _tokens = _getDexTokens();
        uint256 feeLpBalance = _getFeeLpBalance(context);
        uint256[] memory pendingFees = _getSpotAmounts(context, feeLpBalance);
        // fee0
        tokens[0] = _tokens[0];
        claimedAmounts[0] = _getStateAsUint256(CLAIMED_FEE0);
        pendingAmounts[0] = pendingFees[0];
        tokens[1] = _tokens[1];
        claimedAmounts[1] = _getStateAsUint256(CLAIMED_FEE1);
        pendingAmounts[1] = pendingFees[1];
        // farm
        if (n == 3) {
            tokens[2] = _rewardToken(context); // platform
            claimedAmounts[2] = _getStateAsUint256(CLAIMED_FARM_REWARD);
            pendingAmounts[2] = _pendingRewards(context);
        }
    }

    function getTotalSpotAmounts() external view override returns (uint256[] memory amounts) {
        amounts = _getTotalSpotAmounts(_getContext());
    }

    function getSpotAmounts(uint256 lpAmount) external view override returns (uint256[] memory amounts) {
        amounts = _getSpotAmounts(_getContext(), lpAmount);
    }

    function getLiquidityData(uint256[] memory) external pure {
        revert("SushiFarm::InterfaceUnsupported");
    }

    function addLiquidityCurve(uint256[] calldata, uint256) external pure override returns (uint256[] memory, uint256) {
        revert("SushiFarm::InterfaceUnsupported");
    }

    function addLiquidityUniSwapV2(
        uint256[] calldata maxAmounts,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external override returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(maxAmounts.length == 2, "L!2");
        address[] memory tokens = _getDexTokens();
        Context memory context = _getContext();
        // fee
        _updateFeeState(context);
        // approve
        IERC20(tokens[0]).approve(context.router, maxAmounts[0]);
        IERC20(tokens[1]).approve(context.router, maxAmounts[1]);
        // add liquidity
        try
            IUniswapV2Router(context.router).addLiquidity(
                tokens[0],
                tokens[1],
                maxAmounts[0],
                maxAmounts[1],
                minAmounts[0],
                minAmounts[1],
                address(this),
                deadline
            )
        returns (uint256 amount0_, uint256 amount1_, uint256 liquidityAmount_) {
            addedAmounts = new uint256[](2);
            (addedAmounts[0], addedAmounts[1], liquidityAmount) = (amount0_, amount1_, liquidityAmount_);
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("SushiFarm::CallAddLiquidityFail");
        }
        // stake
        _stakeLpToken(context, liquidityAmount);
        _updateK(context);
    }

    function removeLiquidity(
        uint256 lpAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external override returns (uint256[] memory removedAmounts) {
        require(minAmounts.length == 2, "L!2");
        address[] memory tokens = _getDexTokens();
        Context memory context = _getContext();
        // fee
        _updateFeeState(context);
        // unstake
        _unstakeLpToken(context, lpAmount);
        // approve
        IERC20(context.pair).approve(context.router, lpAmount);
        removedAmounts = new uint256[](2);
        // remove
        try
            IUniswapV2Router(context.router).removeLiquidity(
                tokens[0],
                tokens[1],
                lpAmount,
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
            revert("SushiFarm::CallRemoveLiquidityFail");
        }
        _updateK(context);
    }

    function claimFees() external {
        address[] memory tokens = _getDexTokens();
        Context memory context = _getContext();
        _updateFeeState(context);

        uint256 feeLpBalance = _getStateAsUint256(RESERVED_FEE_LP_BALANCE);
        _setStateAsUint256(RESERVED_FEE_LP_BALANCE, 0);

        uint256 farmRewardAmount;
        if (context.farm != address(0)) {
            farmRewardAmount = _pendingRewards(context);
        }
        if (feeLpBalance != 0) {
            _unstakeLpToken(context, feeLpBalance);
            IERC20(context.pair).approve(context.router, feeLpBalance);
            try
                IUniswapV2Router(context.router).removeLiquidity(
                    tokens[0],
                    tokens[1],
                    feeLpBalance,
                    0,
                    0,
                    _vault,
                    type(uint256).max
                )
            returns (uint256 amount0_, uint256 amount1_) {
                _incStateAsUint256(CLAIMED_FEE0, amount0_);
                _incStateAsUint256(CLAIMED_FEE1, amount1_);
                emit TransferFeeToVault(tokens[0], _vault, amount0_);
                emit TransferFeeToVault(tokens[1], _vault, amount1_);
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("SushiFarm::CallRemoveLiquidityFail");
            }
            _updateK(context);
        }
    }

    function _getContext() internal view returns (Context memory config) {
        config = abi.decode(_getConfig(), (Context));
    }

    function _stakeLpToken(Context memory context, uint256 lpAmount) internal {
        if (context.farm == address(0)) {
            return;
        }
        IERC20(context.pair).approve(context.farm, lpAmount);
        try IFarm(context.farm).deposit(context.poolId, lpAmount) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("SushiFarm::CallStakeFail");
        }
    }

    function _unstakeLpToken(Context memory context, uint256 lpAmount) internal {
        if (context.farm == address(0)) {
            return;
        }
        address token = _rewardToken(context);
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        try IFarm(context.farm).withdraw(context.poolId, lpAmount) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("SushiFarm::CallUnStakeFail");
        }
        uint256 rewardAmount = IERC20(token).balanceOf(address(this)) - balanceBefore;
        if (rewardAmount > 0) {
            IERC20(token).safeTransfer(_vault, rewardAmount);
            _incStateAsUint256(CLAIMED_FARM_REWARD, rewardAmount);
            emit TransferFeeToVault(token, _vault, rewardAmount);
        }
    }

    function _getTotalLpBalance(Context memory context) internal view returns (uint256) {
        if (context.farm == address(0)) {
            return IERC20(context.pair).balanceOf(address(this));
        } else {
            return IFarm(context.farm).userInfo(context.poolId, address(this)).amount;
        }
    }

    function _getNetLpBalance(Context memory context) internal view returns (uint256) {
        uint256 equivalentLpBalance = _getEquivalentLpBalance(context);
        uint256 feeLpBalance = _getStateAsUint256(RESERVED_FEE_LP_BALANCE);
        return equivalentLpBalance > feeLpBalance ? equivalentLpBalance - feeLpBalance : 0;
    }

    function _getFeeLpBalance(Context memory context) internal view returns (uint256) {
        uint256 totalLpBalance = _getTotalLpBalance(context);
        uint256 netLpBalance = _getNetLpBalance(context);
        return totalLpBalance - netLpBalance;
    }

    // get new lp balance according to k(t+1) and k(t)
    function _getEquivalentLpBalance(Context memory context) internal view returns (uint256) {
        uint256 poolLpAmount = IERC20(context.pair).totalSupply();
        uint256 lastK = _getStateAsUint256(LAST_K);
        if (lastK == 0) {
            return 0;
        }
        uint256[] memory amounts = _getTotalSpotAmounts(context);
        uint256 k = amounts[0] * amounts[1];
        return (_sqrt(lastK) * poolLpAmount) / _sqrt(k);
    }

    function _getTotalSpotAmounts(Context memory context) internal view returns (uint256[] memory amounts) {
        address[] memory tokens = _getDexTokens();
        amounts = new uint256[](2);
        amounts[0] = IERC20(tokens[0]).balanceOf(context.pair);
        amounts[1] = IERC20(tokens[1]).balanceOf(context.pair);
    }

    function _getSpotAmounts(Context memory context, uint256 lpAmount)
        internal
        view
        returns (uint256[] memory amounts)
    {
        uint256 totalSupply = IERC20(context.pair).totalSupply();
        amounts = new uint256[](2);
        if (totalSupply != 0) {
            amounts = _getTotalSpotAmounts(context);
            amounts[0] = (lpAmount * amounts[0]) / totalSupply;
            amounts[1] = (lpAmount * amounts[1]) / totalSupply;
        }
    }

    function _updateK(Context memory context) internal {
        uint256 lpBalance = _getTotalLpBalance(context);
        if (lpBalance == 0) {
            _setStateAsUint256(LAST_K, 0);
        } else {
            uint256[] memory spotAmounts = _getSpotAmounts(context, lpBalance);
            _setStateAsUint256(LAST_K, spotAmounts[0] * spotAmounts[1]);
        }
    }

    function _updateFeeState(Context memory context) internal {
        uint256 totalLpBalance = _getTotalLpBalance(context);
        uint256 netLpBalance = _getNetLpBalance(context);
        uint256 feeLpBalance = _getStateAsUint256(RESERVED_FEE_LP_BALANCE);
        // net lp balance is an algorithm value, that may comes with math error
        if (totalLpBalance > netLpBalance + feeLpBalance) {
            _incStateAsUint256(RESERVED_FEE_LP_BALANCE, totalLpBalance - netLpBalance - feeLpBalance);
        }
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

    function _rewardToken(Context memory context) internal view virtual returns (address) {
        return IFarm(context.farm).rewardToken();
    }

    function _pendingRewards(Context memory context) internal view virtual returns (uint256) {
        return IFarm(context.farm).pendingReward(context.poolId, address(this));
    }
}
