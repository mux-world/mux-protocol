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
}

interface IGaugeFactory {
    function mint(address gauge) external;
}

interface IGauge {
    function factory() external view returns (address);

    function deposit(
        uint256 _value,
        address _user,
        bool _claim_rewards
    ) external;

    function withdraw(
        uint256 _value,
        address _user,
        bool _claim_rewards
    ) external;

    function balanceOf(address account) external view returns (uint256);

    function claim_rewards(address _addr, address _receiver) external;

    function claimable_tokens(address _addr) external returns (uint256);
}

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
abstract contract CurveFarm is DexAdapter {
    using Address for address;
    using SafeERC20 for IERC20;

    struct Context {
        address pool;
        address lpToken;
        address farm;
        address rewardToken;
        uint8 quoteIndex;
    }

    bytes32 constant CLAIMED_FARM_REWARD = keccak256("CLAIMED_FARM_REWARD");

    function getFees()
        external
        returns (
            address[] memory tokens,
            uint256[] memory claimedAmounts,
            uint256[] memory pendingAmounts
        )
    {
        Context memory context = _getContext();
        address[] memory dexTokens = _getDexTokens();
        uint256 n = context.rewardToken == address(0) ? dexTokens.length : dexTokens.length + 1;
        tokens = new address[](n);
        for (uint256 i = 0; i < dexTokens.length; i++) {
            tokens[i] = dexTokens[i];
        }
        // 0 -- no fee
        claimedAmounts = new uint256[](n);
        pendingAmounts = new uint256[](n);
        // farm rewards
        if (context.farm != address(0)) {
            tokens[n - 1] = context.rewardToken;
            pendingAmounts[n - 1] = IGauge(context.farm).claimable_tokens(address(this));
            claimedAmounts[n - 1] = _getStateAsUint256(CLAIMED_FARM_REWARD);
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
        revert("CurveFarm::InterfaceUnsupported");
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
            IERC20(tokens[i]).approve(context.pool, maxAmounts[i]);
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

    function claimFees() external {
        Context memory context = _getContext();
        address factory = IGauge(context.farm).factory();
        if (factory != address(0)) {
            IGaugeFactory(factory).mint(context.farm);
        }
        IGauge(context.farm).claim_rewards(address(this), address(this));
        uint256 rewardAmount = IERC20(context.rewardToken).balanceOf(address(this));
        if (rewardAmount > 0) {
            IERC20(context.rewardToken).safeTransfer(_vault, rewardAmount);
            _incStateAsUint256(CLAIMED_FARM_REWARD, rewardAmount);
            emit TransferFeeToVault(context.rewardToken, _vault, rewardAmount);
        }
    }

    function _stakeLpToken(Context memory context, uint256 lpAmount) internal virtual {
        if (context.farm == address(0)) {
            return;
        }
        IERC20(context.lpToken).approve(context.farm, lpAmount);
        try IGauge(context.farm).deposit(lpAmount, address(this), false) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("SushIGauge::CallStakeFail");
        }
    }

    function _unstakeLpToken(Context memory context, uint256 lpAmount) internal virtual {
        if (context.farm == address(0)) {
            return;
        }
        try IGauge(context.farm).withdraw(lpAmount, address(this), false) {} catch Error(string memory reason) {
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
        if (context.farm != address(0)) {
            return IGauge(context.farm).balanceOf(address(this));
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
