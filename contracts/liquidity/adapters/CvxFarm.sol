// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./DexAdapter.sol";

interface ICurvePool {
    function coins(uint256 index) external view returns (address);

    function balances(uint256 index) external view returns (uint256);

    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256 dy);

    function add_liquidity(uint256[3] memory _amounts, uint256 _min_mint_amount) external;

    function remove_liquidity(uint256 _burn_amount, uint256[3] memory _min_amounts) external;

    function calc_token_amount(uint256[3] memory _amounts, bool _is_deposit) external view returns (uint256);
}

interface IDeposit {
    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    function poolInfo(uint256 index) external view returns (PoolInfo memory);

    function staker() external view returns (address);

    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);
}

interface IRewards {
    function balanceOf(address) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getReward(address _account, bool _claimExtras) external returns (bool);
}

interface ICvxToken {
    function totalSupply() external view returns (uint256);

    function reductionPerCliff() external view returns (uint256);

    function totalCliffs() external view returns (uint256);

    function maxSupply() external view returns (uint256);
}

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
abstract contract CvxFarm is DexAdapter {
    using Address for address;
    using SafeERC20 for IERC20;

    address public constant CRV_TOKEN = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX_TOKEN = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    struct Context {
        address pool;
        address lpToken;
        address deposit;
        uint256 poolId;
        address rewards;
        uint8 quoteIndex;
    }

    bytes32 constant CLAIMED_CRV_REWARD = keccak256("CLAIMED_CRV_REWARD");
    bytes32 constant CLAIMED_CVX_REWARD = keccak256("CLAIMED_CVX_REWARD");

    function getFees()
        external
        virtual
        returns (
            address[] memory tokens,
            uint256[] memory claimedAmounts,
            uint256[] memory pendingAmounts
        )
    {
        Context memory context = _getContext();
        address[] memory dexTokens = _getDexTokens();
        uint256 n = dexTokens.length;
        tokens = new address[](n + 2);
        for (uint256 i = 0; i < n; i++) {
            tokens[i] = dexTokens[i];
        }
        // 0 -- no fee
        claimedAmounts = new uint256[](n + 2);
        pendingAmounts = new uint256[](n + 2);

        uint256 earnedAmount = IRewards(context.rewards).earned(address(this));
        // farm rewards
        tokens[n] = CRV_TOKEN;
        pendingAmounts[n] = earnedAmount;
        claimedAmounts[n] = _getStateAsUint256(CLAIMED_CRV_REWARD);

        tokens[n + 1] = CVX_TOKEN;
        pendingAmounts[n + 1] = _getCvxMintAmount(earnedAmount);
        claimedAmounts[n + 1] = _getStateAsUint256(CLAIMED_CVX_REWARD);
    }

    function _getCvxMintAmount(uint256 amount) internal view returns (uint256 mintAmount) {
        uint256 supply = ICvxToken(CVX_TOKEN).totalSupply();
        if (supply == 0) {
            mintAmount = amount;
            return mintAmount;
        }
        uint256 reductionPerCliff = ICvxToken(CVX_TOKEN).reductionPerCliff();
        uint256 totalCliffs = ICvxToken(CVX_TOKEN).totalCliffs();
        uint256 maxSupply = ICvxToken(CVX_TOKEN).maxSupply();
        uint256 cliff = supply / reductionPerCliff;
        if (cliff < totalCliffs) {
            uint256 reduction = totalCliffs - cliff;
            mintAmount = (amount * reduction) / totalCliffs;
            uint256 amtTillMax = maxSupply - supply;
            if (mintAmount > amtTillMax) {
                mintAmount = amtTillMax;
            }
        }
    }

    function getTotalSpotAmounts() external view returns (uint256[] memory amounts) {
        return _getTotalSpotAmounts(_getContext());
    }

    function getLpBalance() public view override returns (uint256) {
        return _getLpBalance(_getContext());
    }

    function getSpotAmounts(uint256 lpAmount) public view override returns (uint256[] memory amounts) {
        Context memory context = _getContext();
        uint256 totalSupply = IERC20(context.lpToken).totalSupply();
        amounts = _getTotalSpotAmounts(context);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = totalSupply == 0 ? 0 : (amounts[i] * lpAmount) / totalSupply;
        }
    }

    function getLiquidityData(uint256[] memory maxAmounts)
        external
        view
        returns (
            uint256[] memory prices,
            uint256 quoteIndex,
            uint256[] memory totalSpotAmounts,
            uint256 minLpAmount
        )
    {
        Context memory context = _getContext();
        (prices, quoteIndex, totalSpotAmounts, minLpAmount) = _getLiquidityData(context, maxAmounts);
    }

    function addLiquidityUniSwapV2(
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external pure override returns (uint256[] memory, uint256) {
        revert("CvxFarm::InterfaceUnsupported");
    }

    function addLiquidityCurve(uint256[] calldata maxAmounts, uint256 minLpAmount)
        external
        override
        returns (uint256[] memory addedAmounts, uint256 liquidityAmount)
    {
        Context memory context = _getContext();
        address[] memory tokens = _getDexTokens();
        require(maxAmounts.length == tokens.length, "LEN");
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeApprove(context.pool, 0);
            IERC20(tokens[i]).safeApprove(context.pool, maxAmounts[i]);
        }
        liquidityAmount = _addLiquidity(context, maxAmounts, minLpAmount);
        addedAmounts = maxAmounts;
        _stakeLpToken(context, liquidityAmount);
    }

    function removeLiquidity(
        uint256 lpAmount,
        uint256[] calldata minAmounts,
        uint256
    ) public override returns (uint256[] memory removedAmounts) {
        Context memory context = _getContext();
        _unstakeLpToken(context, lpAmount);
        IERC20(context.lpToken).approve(context.pool, lpAmount);
        removedAmounts = _removeLiquidity(context, lpAmount, minAmounts);
    }

    function claimFees() external virtual {
        Context memory context = _getContext();
        IRewards(context.rewards).getReward(address(this), true);
        {
            uint256 rewardAmount = IERC20(CRV_TOKEN).balanceOf(address(this));
            if (rewardAmount > 0) {
                IERC20(CRV_TOKEN).safeTransfer(_vault, rewardAmount);
                _incStateAsUint256(CLAIMED_CRV_REWARD, rewardAmount);
                emit TransferFeeToVault(CRV_TOKEN, _vault, rewardAmount);
            }
        }
        {
            uint256 rewardAmount = IERC20(CVX_TOKEN).balanceOf(address(this));
            if (rewardAmount > 0) {
                IERC20(CVX_TOKEN).safeTransfer(_vault, rewardAmount);
                _incStateAsUint256(CLAIMED_CVX_REWARD, rewardAmount);
                emit TransferFeeToVault(CVX_TOKEN, _vault, rewardAmount);
            }
        }
    }

    function _stakeLpToken(Context memory context, uint256 lpAmount) internal virtual {
        if (context.deposit == address(0)) {
            return;
        }
        IERC20(context.lpToken).approve(context.deposit, lpAmount);
        try IDeposit(context.deposit).deposit(context.poolId, lpAmount, true) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("SushIGauge::CallStakeFail");
        }
    }

    function _unstakeLpToken(Context memory context, uint256 lpAmount) internal virtual {
        if (context.deposit == address(0)) {
            return;
        }
        try IDeposit(context.deposit).withdraw(context.poolId, lpAmount) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("SushIGauge::CallUnStakeFail");
        }
    }

    function _getPrices(Context memory context, uint256 tokenCount)
        internal
        view
        virtual
        returns (uint256[] memory prices, uint256 quoteIndex)
    {
        prices = new uint256[](tokenCount);
        quoteIndex = context.quoteIndex;
        address[] memory tokens = _getDexTokens();
        for (uint128 i = 0; i < tokenCount; i++) {
            uint8 decimals = IDecimals(tokens[i]).decimals();
            if (i == quoteIndex) {
                prices[i] = 10**decimals; // as reference
            } else {
                try ICurvePool(context.pool).get_dy(i, quoteIndex, 10**decimals) returns (uint256 dy) {
                    prices[i] = dy;
                } catch Error(string memory reason) {
                    revert(reason);
                } catch {
                    revert("SushIGauge::CallGetPriceFail");
                }
            }
        }
    }

    function _getContext() internal view returns (Context memory config) {
        config = abi.decode(_getConfig(), (Context));
    }

    function _getLpBalance(Context memory context) internal view returns (uint256) {
        // if (context.deposit != address(0)) {
        //     address token = IDeposit(context.deposit).poolInfo(context.poolId).token;
        //     return IERC20(token).balanceOf(address(this));
        // } else {
        //     return IERC20(context.lpToken).balanceOf(address(this));
        // }

        if (context.rewards != address(0)) {
            return IERC20(context.rewards).balanceOf(address(this));
        } else {
            return IERC20(context.lpToken).balanceOf(address(this));
        }
    }

    function _getTokenIndex(address token) internal view virtual returns (int128 index) {
        address[] memory tokens = _getDexTokens();
        for (uint128 i = 0; i < tokens.length; i++) {
            if (token == tokens[i]) {
                return int128(i);
            }
        }
        return -1;
    }

    function _getLiquidityData(Context memory context, uint256[] memory maxAmounts)
        internal
        view
        virtual
        returns (
            uint256[] memory prices,
            uint256 quoteIndex,
            uint256[] memory totalSpotAmounts,
            uint256 minLpAmount
        );

    function _getTotalSpotAmounts(Context memory context) internal view virtual returns (uint256[] memory amounts);

    function _addLiquidity(
        Context memory context,
        uint256[] memory maxAmounts,
        uint256 minShareAmount
    ) public virtual returns (uint256 shareAmount);

    function _removeLiquidity(
        Context memory context,
        uint256 shareAmount,
        uint256[] memory minAmounts
    ) public virtual returns (uint256[] memory amounts);
}
