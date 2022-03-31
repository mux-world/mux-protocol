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
contract CurveFarmModule is Module {
    using Address for address;
    using SafeERC20 for IERC20;

    uint256 public constant V_PRICE_INDEX = 0;
    address public immutable pool;
    address public immutable tokenA;
    address public immutable tokenB;
    address public immutable stake;

    constructor(
        address pool_,
        address tokenA_,
        address tokenB_,
        address stake_
    ) {
        pool = pool_;
        tokenA = tokenA_;
        tokenB = tokenB_;
        stake = stake_;
    }

    function id() public pure override returns (bytes32) {
        return LibUtils.toBytes32("crv-demo-farm-mod");
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
        uint256 shareAmount = hasFee ? _getFeeShareAmount(feeAmounts) : 0;
        return _getLpBalance() - shareAmount;
    }

    function getFees() public view returns (uint256[] memory feeAmounts) {
        (, feeAmounts) = _getFees();
    }

    function getSpotAmounts(uint256 shareAmount) public view returns (uint256[] memory amounts) {
        uint256 totalSupply = IERC20(pool).totalSupply();
        (uint256 reservedA, uint256 reservedB) = _getReserves();
        amounts = new uint256[](2);
        amounts[0] = (reservedA * shareAmount) / totalSupply;
        amounts[1] = (reservedB * shareAmount) / totalSupply;
    }

    function addLiquidity(
        uint256[] calldata maxAmounts,
        uint256[] calldata minAmounts,
        uint256
    ) public returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(maxAmounts.length == 2, "L!2");
        require(maxAmounts.length == minAmounts.length, "L!L");
        (bool hasFee, uint256[] memory feeAmounts) = _getFees();
        if (hasFee) {
            uint256 feeShareAmount = _getFeeShareAmount(feeAmounts);
            IERC20(pool).approve(pool, feeShareAmount);
            ICurve2Pool(pool).remove_liquidity(feeShareAmount, _toArray2(feeAmounts));
        }
        IERC20(tokenA).approve(pool, maxAmounts[0]);
        IERC20(tokenB).approve(pool, maxAmounts[1]);
        liquidityAmount = ICurve2Pool(pool).add_liquidity(_toArray2(maxAmounts), 0);
        addedAmounts = maxAmounts;
        // TODO: stake to somewhere
        if (stake != address(0)) {
            IERC20(pool).approve(stake, liquidityAmount);
            IStake(stake).stake(liquidityAmount);
        }
        _writeState(V_PRICE_INDEX, bytes32(ICurve2Pool(pool).get_virtual_price()));
    }

    function removeLiquidity(
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256
    ) public returns (uint256[] memory removedAmounts, uint256[] memory feeAmounts) {
        require(minAmounts.length == 2, "L!2");
        (, feeAmounts) = _getFees();
        uint256 feeShareAmount = _getFeeShareAmount(feeAmounts);
        if (stake != address(0)) {
            IStake(stake).redeem(shareAmount + feeShareAmount);
        }
        uint256[2] memory amounts;
        amounts[0] = minAmounts[0] + feeAmounts[0];
        amounts[1] = minAmounts[1] + feeAmounts[1];
        removedAmounts = new uint256[](2);
        removedAmounts = _toSlice(ICurve2Pool(pool).remove_liquidity(shareAmount + feeShareAmount, amounts));
        _writeState(V_PRICE_INDEX, bytes32(ICurve2Pool(pool).get_virtual_price()));
    }

    function _getLpBalance() internal view returns (uint256) {
        if (stake != address(0)) {
            return IStake(stake).balanceOf(address(this));
        } else {
            return IERC20(pool).balanceOf(address(this));
        }
    }

    function _getFees() internal view returns (bool hasFee, uint256[] memory feeAmounts) {
        uint256 lastVPrice = uint256(_readState(V_PRICE_INDEX));
        uint256 vPrice = ICurve2Pool(pool).get_virtual_price();
        uint256 rate = vPrice > lastVPrice ? vPrice - lastVPrice : 0;
        feeAmounts = new uint256[](2);
        if (rate != 0) {
            hasFee = true;
            uint256 shareAmount = IERC20(pool).balanceOf(address(this));
            uint256 totalSupply = IERC20(pool).totalSupply();
            (uint256 reservedA, uint256 reservedB) = _getReserves();
            feeAmounts[0] = (((reservedA * shareAmount) / totalSupply) * rate) / vPrice;
            feeAmounts[1] = (((reservedB * shareAmount) / totalSupply) * rate) / vPrice;
        }
    }

    function _getFeeShareAmount(uint256[] memory feeAmounts) internal view returns (uint256 shareAmount) {
        require(feeAmounts.length == 2, "F!2");
        uint256 totalSupply = IERC20(pool).totalSupply();
        (uint256 reservedA, uint256 reservedB) = _getReserves();
        uint256 shareAmountA = (feeAmounts[0] * totalSupply) / reservedA;
        uint256 shareAmountB = (feeAmounts[1] * totalSupply) / reservedB;
        shareAmount = shareAmountA >= shareAmountB ? shareAmountA : shareAmountB;
    }

    function _toArray2(uint256[] memory amounts_) internal pure returns (uint256[2] memory amounts) {
        require(amounts_.length == 2, "L!2");
        amounts[0] = amounts_[0];
        amounts[1] = amounts_[1];
    }

    function _toSlice(uint256[2] memory amounts_) internal pure returns (uint256[] memory amounts) {
        require(amounts_.length == 2, "L!2");
        amounts = new uint256[](2);
        amounts[0] = amounts_[0];
        amounts[1] = amounts_[1];
    }

    function _getReserves() internal view returns (uint256, uint256) {
        return (ICurve2Pool(pool).balances(0), ICurve2Pool(pool).balances(1));
    }
}

interface ICurve2Pool {
    function balances(uint256 index) external view returns (uint256);

    function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external returns (uint256);

    function remove_liquidity(uint256 _burn_amount, uint256[2] memory _min_amounts)
        external
        returns (uint256[2] memory);

    function get_virtual_price() external view returns (uint256);
}

interface IStake {
    function stake(uint256 amount) external;

    function redeem(uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);
}
