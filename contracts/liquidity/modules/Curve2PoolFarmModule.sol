// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./CurveFarmModule.sol";

import "hardhat/console.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract Curve2PoolFarmModule is CurveFarmModule {
    using Address for address;
    using SafeERC20 for IERC20;

    uint256 constant TOKEN_COUNT = 2;

    constructor(
        address pool_,
        address token0_,
        address token1_,
        address stake_
    ) CurveFarmModule(pool_, token0_, token1_, address(0), TOKEN_COUNT, stake_) {
        // avoid wrong order of `_getReserves` return values
        require(ICurve2Pool(pool_).coins(0) == token0, "!T0");
        require(ICurve2Pool(pool_).coins(1) == token1, "!T1");
    }

    function id() public pure override returns (bytes32) {
        return LibUtils.toBytes32("crv-2pool-farm-mod");
    }

    function _approve(address spender, uint256[] memory amounts) internal virtual override {
        require(amounts.length == TOKEN_COUNT, "!L");
        IERC20(token0).approve(spender, amounts[0]);
        IERC20(token1).approve(spender, amounts[1]);
    }

    function _calcLpAmount(uint256[] memory amounts, bool isDeposit) internal view virtual override returns (uint256) {
        uint256[2] memory _amounts;
        _amounts[0] = amounts[0];
        _amounts[1] = amounts[1];
        return ICurve2Pool(pool).calc_token_amount(_amounts, isDeposit);
    }

    function _getReserves() internal view virtual override returns (uint256[] memory reserves) {
        reserves = new uint256[](TOKEN_COUNT);
        reserves[0] = ICurve2Pool(pool).balances(0);
        reserves[1] = ICurve2Pool(pool).balances(1);
    }

    function _addCurveLiquidity(uint256[] memory maxAmounts, uint256 minShareAmount)
        public
        virtual
        override
        returns (uint256 shareAmount)
    {
        require(maxAmounts.length == TOKEN_COUNT, "!L");
        uint256[2] memory amounts;
        amounts[0] = maxAmounts[0];
        amounts[1] = maxAmounts[1];
        return ICurve2Pool(pool).add_liquidity(amounts, minShareAmount);
    }

    function _removeCurveLiquidity(uint256 shareAmount, uint256[] memory minAmounts)
        public
        virtual
        override
        returns (uint256[] memory removedAmounts)
    {
        require(minAmounts.length == TOKEN_COUNT, "!L");
        uint256[2] memory _minAmounts;
        _minAmounts[0] = minAmounts[0];
        _minAmounts[1] = minAmounts[1];
        uint256[2] memory _removedAmounts = ICurve2Pool(pool).remove_liquidity(shareAmount, _minAmounts);
        removedAmounts = new uint256[](2);
        removedAmounts[0] = _removedAmounts[0];
        removedAmounts[1] = _removedAmounts[1];
    }
}

interface ICurve2Pool {
    function coins(uint256 index) external view returns (address);

    function balances(uint256 index) external view returns (uint256);

    function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external returns (uint256);

    function remove_liquidity(uint256 _burn_amount, uint256[2] memory _min_amounts)
        external
        returns (uint256[2] memory);

    function calc_token_amount(uint256[2] memory _amounts, bool _is_deposit) external view returns (uint256);
}
