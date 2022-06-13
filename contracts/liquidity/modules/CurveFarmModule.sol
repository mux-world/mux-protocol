// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "../../interfaces/IDexLiquidityModule.sol";
import "./DexModule.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
abstract contract CurveFarmModule is DexModule, IDexLiquidityModule {
    using Address for address;
    using SafeERC20 for IERC20;

    address public immutable pool;
    address public immutable token0;
    address public immutable token1;
    address public immutable token2;
    uint256 public immutable tokenCount;
    address public immutable stake;

    constructor(
        address pool_,
        address token0_,
        address token1_,
        address token2_,
        uint256 tokenCount_,
        address stake_
    ) {
        pool = pool_;
        stake = stake_;
        token0 = token0_;
        token1 = token1_;
        token2 = token2_;
        tokenCount = tokenCount_;
    }

    function id() public pure virtual override returns (bytes32);

    function meta()
        public
        view
        virtual
        override
        returns (
            bytes32[] memory methodIds,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        )
    {
        methodIds = new bytes32[](8);
        methodIds[0] = LibUtils.toBytes32("getLpBalance");
        methodIds[1] = LibUtils.toBytes32("getFees");
        methodIds[2] = LibUtils.toBytes32("getSpotAmounts");
        methodIds[3] = LibUtils.toBytes32("addLiquidity");
        methodIds[4] = LibUtils.toBytes32("removeLiquidity");
        methodIds[5] = LibUtils.toBytes32("getValidationData");
        methodIds[6] = LibUtils.toBytes32("getAmountOut");
        methodIds[7] = LibUtils.toBytes32("getTotalSpotAmounts");
        selectors = new bytes4[](8);
        selectors[0] = this.getLpBalance.selector;
        selectors[1] = this.getFees.selector;
        selectors[2] = this.getSpotAmounts.selector;
        selectors[3] = this.addLiquidity.selector;
        selectors[4] = this.removeLiquidity.selector;
        selectors[5] = this.getValidationData.selector;
        selectors[6] = this.getAmountOut.selector;
        selectors[7] = this.getTotalSpotAmounts.selector;
        initialStates = new bytes32[](1);
    }

    function getLpBalance() public view override returns (uint256) {
        return _getLpBalance();
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
        rewardTokens = new address[](tokenCount);
        (, rewardTokens) = tokens();
        collectedFeeAmounts = new uint256[](tokenCount);
        pendingFeeAmounts = new uint256[](tokenCount);
    }

    function getTotalSpotAmounts() public view returns (uint256[] memory amounts) {
        amounts = _getReserves();
    }

    function getSpotAmounts(uint256 shareAmount) public view override returns (uint256[] memory amounts) {
        uint256 totalSupply = IERC20(pool).totalSupply();
        amounts = _getReserves();
        for (uint256 i = 0; i < tokenCount; i++) {
            amounts[i] = (amounts[i] * shareAmount) / totalSupply;
        }
    }

    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view override returns (uint256 amountOut) {
        int128 indexIn = _getTokenIndex(tokenIn);
        int128 indexOut = _getTokenIndex(tokenOut);
        require(indexIn >= 0 && indexOut >= 0, "Unknown token");
        require(indexIn != indexOut, "In & out are same token");
        return ICurvePool(pool).get_dy_underlying(indexIn, indexOut, amountIn);
    }

    function addLiquidity(
        uint256[] calldata maxAmounts,
        uint256,
        bytes memory validationData
    ) public override returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(maxAmounts.length == tokenCount, "!L");
        uint256 minShareAmount;
        if (validationData.length > 0) {
            minShareAmount = abi.decode(validationData, (uint256));
        }
        _approve(pool, maxAmounts);
        liquidityAmount = _addCurveLiquidity(maxAmounts, minShareAmount);
        addedAmounts = maxAmounts;
        if (stake != address(0)) {
            try IERC20(pool).approve(stake, liquidityAmount) {} catch {
                revert("Fail to call approve on pool");
            }
            try IStake(stake).deposit(liquidityAmount, address(this), false) {} catch {
                revert("Fail to call deposit on stake");
            }
        }
    }

    function removeLiquidity(
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256
    ) public override returns (uint256[] memory removedAmounts) {
        require(minAmounts.length == tokenCount, "!L");
        if (stake != address(0)) {
            // NOTE: if the stake need approve, add it below
            IStake(stake).withdraw(shareAmount, address(this), false);
        }
        removedAmounts = _removeCurveLiquidity(shareAmount, minAmounts);
    }

    function _getLpBalance() internal view returns (uint256) {
        if (stake != address(0)) {
            return IStake(stake).balanceOf(address(this));
        } else {
            return IERC20(pool).balanceOf(address(this));
        }
    }

    function _getTokenIndex(address token) internal view virtual returns (int128 index);

    function _approve(address spender, uint256[] memory amounts) internal virtual;

    function _calcLpAmount(uint256[] memory minAmounts, bool isDeposit) internal view virtual returns (uint256);

    function _getReserves() internal view virtual returns (uint256[] memory reserves);

    function _addCurveLiquidity(uint256[] memory maxAmounts, uint256 minShareAmount)
        public
        virtual
        returns (uint256 shareAmount);

    function _removeCurveLiquidity(uint256 shareAmount, uint256[] memory minAmounts)
        public
        virtual
        returns (uint256[] memory amounts);
}

interface ICurvePool {
    function get_dy_underlying(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256 dy);
}

interface IStake {
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
}
