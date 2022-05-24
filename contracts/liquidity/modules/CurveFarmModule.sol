// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./Module.sol";

import "hardhat/console.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
abstract contract CurveFarmModule is Module {
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
        return _getLpBalance();
    }

    function getFees() public view returns (uint256[] memory feeAmounts) {
        feeAmounts = new uint256[](tokenCount);
    }

    function getSpotAmounts(uint256 shareAmount) public view returns (uint256[] memory amounts) {
        uint256 totalSupply = IERC20(pool).totalSupply();
        amounts = _getReserves();
        for (uint256 i = 0; i < tokenCount; i++) {
            amounts[i] = (amounts[i] * shareAmount) / totalSupply;
        }
    }

    function addLiquidity(
        uint256[] calldata maxAmounts,
        uint256[] calldata minAmounts,
        uint256
    ) public returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(maxAmounts.length == tokenCount, "!L");
        require(maxAmounts.length == minAmounts.length, "L!L");
        _approve(pool, maxAmounts);
        uint256 minShareAmount = _calcLpAmount(minAmounts, true);
        liquidityAmount = _addCurveLiquidity(maxAmounts, minShareAmount);
        addedAmounts = maxAmounts;
        if (stake != address(0)) {
            IERC20(pool).approve(stake, liquidityAmount);
            IStake(stake).stake(liquidityAmount);
        }
    }

    function removeLiquidity(
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256
    ) public returns (uint256[] memory removedAmounts, uint256[] memory feeAmounts) {
        require(minAmounts.length == tokenCount, "!L");
        if (stake != address(0)) {
            // NOTE: if the stake need approve, add it below
            IStake(stake).redeem(shareAmount);
        }
        removedAmounts = _removeCurveLiquidity(shareAmount, minAmounts);
        feeAmounts = new uint256[](tokenCount); // 0
    }

    function _getLpBalance() internal view returns (uint256) {
        if (stake != address(0)) {
            return IStake(stake).balanceOf(address(this));
        } else {
            return IERC20(pool).balanceOf(address(this));
        }
    }

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
    function balances(uint256 index) external view returns (uint256);

    function calc_token_amount(uint256[2] memory _amounts, bool _is_deposit) external view returns (uint256);
}

interface IStake {
    function stake(uint256 amount) external;

    function redeem(uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);
}
