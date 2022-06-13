// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./CurveFarmModule.sol";

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract Curve3PoolFarmModule is CurveFarmModule {
    using Address for address;
    using SafeERC20 for IERC20;

    uint256 constant TOKEN_COUNT = 3;

    constructor(
        address pool_,
        address token0_,
        address token1_,
        address token2_,
        address stake_
    ) CurveFarmModule(pool_, token0_, token1_, token2_, TOKEN_COUNT, stake_) {
        // avoid wrong order of `_getReserves` return values
        require(ICurve2Pool(pool_).coins(0) == token0, "!T0");
        require(ICurve2Pool(pool_).coins(1) == token1, "!T1");
        require(ICurve2Pool(pool_).coins(2) == token2, "!T2");
    }

    function id() public pure override returns (bytes32) {
        return LibUtils.toBytes32("crv-3pool-farm-mod");
    }

    function tokens() public view override returns (bool needCheck_, address[] memory tokens_) {
        needCheck_ = true;
        tokens_ = new address[](3);
        tokens_[0] = token0;
        tokens_[1] = token1;
        tokens_[2] = token2;
    }

    function getValidationData(uint256[] memory amounts) public view override returns (bytes memory data) {
        return abi.encode(ICurve2Pool(pool).calc_token_amount(_toArray(amounts), true));
    }

    function _approve(address spender, uint256[] memory amounts) internal virtual override {
        require(amounts.length == TOKEN_COUNT, "!L");
        IERC20(token0).approve(spender, amounts[0]);
        IERC20(token1).approve(spender, amounts[1]);
        IERC20(token2).approve(spender, amounts[2]);
    }

    function _getTokenIndex(address token) internal view override returns (int128 index) {
        if (token == token0) {
            return 0;
        } else if (token == token1) {
            return 1;
        } else if (token == token2) {
            return 2;
        }
        return -1;
    }

    function _calcLpAmount(uint256[] memory amounts, bool isDeposit) internal view virtual override returns (uint256) {
        uint256[TOKEN_COUNT] memory _amounts;
        _amounts[0] = amounts[0];
        _amounts[1] = amounts[1];
        _amounts[2] = amounts[2];
        return ICurve2Pool(pool).calc_token_amount(_amounts, isDeposit);
    }

    function _getReserves() internal view virtual override returns (uint256[] memory reserves) {
        reserves = new uint256[](TOKEN_COUNT);
        reserves[0] = ICurve2Pool(pool).balances(0);
        reserves[1] = ICurve2Pool(pool).balances(1);
        reserves[2] = ICurve2Pool(pool).balances(2);
    }

    function _addCurveLiquidity(uint256[] memory maxAmounts, uint256 minShareAmount)
        public
        virtual
        override
        returns (uint256 shareAmount)
    {
        require(maxAmounts.length == TOKEN_COUNT, "!L");
        uint256[TOKEN_COUNT] memory _maxAmounts = _toArray(maxAmounts);
        return ICurve2Pool(pool).add_liquidity(_maxAmounts, minShareAmount);
    }

    function _removeCurveLiquidity(uint256 shareAmount, uint256[] memory minAmounts)
        public
        virtual
        override
        returns (uint256[] memory removedAmounts)
    {
        require(minAmounts.length == TOKEN_COUNT, "!L");
        uint256[TOKEN_COUNT] memory _minAmounts = _toArray(minAmounts);
        uint256[TOKEN_COUNT] memory _removedAmounts = ICurve2Pool(pool).remove_liquidity(shareAmount, _minAmounts);
        removedAmounts = _toSlice(_removedAmounts);
    }

    function _toArray(uint256[] memory _in) internal pure returns (uint256[TOKEN_COUNT] memory _out) {
        require(_in.length == TOKEN_COUNT, "LEN");
        _out[0] = _in[0];
        _out[1] = _in[1];
        _out[2] = _in[2];
    }

    function _toSlice(uint256[TOKEN_COUNT] memory _in) internal pure returns (uint256[] memory _out) {
        _out = new uint256[](TOKEN_COUNT);
        _out[0] = _in[0];
        _out[1] = _in[1];
        _out[2] = _in[2];
    }
}

interface ICurve2Pool {
    function FEE_DENOMINATOR() external view returns (uint256);

    function admin_fee() external view returns (uint256);

    function coins(uint256 index) external view returns (address);

    function balances(uint256 index) external view returns (uint256);

    function add_liquidity(uint256[3] memory _amounts, uint256 _min_mint_amount) external returns (uint256);

    function remove_liquidity(uint256 _burn_amount, uint256[3] memory _min_amounts)
        external
        returns (uint256[3] memory);

    function calc_token_amount(uint256[3] memory _amounts, bool _is_deposit) external view returns (uint256);
}
