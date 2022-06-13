// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./MockUniV2Pool.sol";

contract MockCurve2Pool is MockUniV2Pool {
    constructor(address tokenA_, address tokenB_) MockUniV2Pool(tokenA_, tokenB_) {}

    function coins(uint256 index) public view returns (address) {
        if (index == 0) {
            return _tokenA;
        } else if (index == 1) {
            return _tokenB;
        } else {
            revert("Index out of range");
        }
    }

    function balances() external view returns (uint256[2] memory balances_) {
        balances_[0] = reserveA;
        balances_[1] = reserveB;
    }

    function get_virtual_price() external view returns (uint256) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            return 0;
        }
        return (reserveA * reserveB) / totalSupply_;
    }

    function add_liquidity(
        uint256[2] memory _amounts,
        uint256 _min_mint_amount,
        address _receiver
    ) public returns (uint256) {
        (, , uint256 liquidity) = addLiquidity(
            _tokenA,
            _tokenB,
            _amounts[0],
            _amounts[1],
            0,
            0,
            _receiver,
            type(uint256).max
        );
        require(liquidity >= _min_mint_amount, "MMA");
        return liquidity;
    }

    function remove_liquidity(
        uint256 _burn_amount,
        uint256[2] memory _min_amounts,
        address _receiver
    ) public returns (uint256[2] memory) {
        uint256[2] memory amounts;
        (amounts[0], amounts[1]) = removeLiquidity(
            _tokenA,
            _tokenB,
            _burn_amount,
            _min_amounts[0],
            _min_amounts[1],
            _receiver,
            type(uint256).max
        );
        return amounts;
    }
}
