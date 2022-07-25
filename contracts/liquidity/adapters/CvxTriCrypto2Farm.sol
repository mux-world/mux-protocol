// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./CvxFarm.sol";

interface ICurve3Pool {
    function add_liquidity(uint256[3] memory _amounts, uint256 _min_mint_amount) external;

    function remove_liquidity(uint256 _burn_amount, uint256[3] memory _min_amounts) external;

    function calc_token_amount(uint256[3] memory _amounts, bool _is_deposit) external view returns (uint256);
}

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract CvxTriCrypto2Farm is CvxFarm {
    uint256 constant TOKEN_COUNT = 3;

    function initializeAdapter(bytes memory initialData) external virtual {
        Context memory context = abi.decode(initialData, (Context));
        require(context.pool != address(0), "!A0");
        require(context.lpToken != address(0), "!A1");
        require(context.deposit != address(0), "!A2");
        require(context.rewards != address(0), "!A3");
        require(context.quoteIndex < TOKEN_COUNT, "!A4");
        address[] memory tokens = _getDexTokens();
        require(tokens.length == TOKEN_COUNT, "LEN");
        for (uint256 i = 0; i < TOKEN_COUNT; i++) {
            require(tokens[i] == ICurvePool(context.pool).coins(i), "!TK");
        }
        _dexData[_dexId()].config = initialData;
    }

    function _getLiquidityData(Context memory context, uint256[] memory maxAmounts)
        internal
        view
        override
        returns (
            uint256[] memory prices,
            uint256 quoteIndex,
            uint256[] memory totalSpotAmounts,
            uint256 minLpAmount
        )
    {
        (prices, quoteIndex) = _getPrices(context, TOKEN_COUNT);
        totalSpotAmounts = _getTotalSpotAmounts(context);
        try ICurve3Pool(context.pool).calc_token_amount(_toArray(maxAmounts), true) returns (uint256 _minLpAmount) {
            minLpAmount = _minLpAmount;
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("CvxTriCrypto2Farm::CallCalcTokenAmountFail");
        }
    }

    function _getTotalSpotAmounts(Context memory context) internal view override returns (uint256[] memory amounts) {
        amounts = new uint256[](TOKEN_COUNT);
        for (uint128 i = 0; i < TOKEN_COUNT; i++) {
            amounts[i] = ICurvePool(context.pool).balances(i);
        }
    }

    function _addLiquidity(
        Context memory context,
        uint256[] memory maxAmounts,
        uint256 minLpAmount
    ) public virtual override returns (uint256 lpAmount) {
        require(maxAmounts.length == TOKEN_COUNT, "CvxTriCrypto2Farm::WrongArrayLength");
        uint256 balanceBefore = IERC20(context.lpToken).balanceOf(address(this));
        try ICurve3Pool(context.pool).add_liquidity(_toArray(maxAmounts), minLpAmount) {
            lpAmount = IERC20(context.lpToken).balanceOf(address(this)) - balanceBefore;
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("CvxTriCrypto2Farm::CallAddLiquidityFail");
        }
    }

    function _removeLiquidity(
        Context memory context,
        uint256 lpAmount,
        uint256[] memory minAmounts
    ) public virtual override returns (uint256[] memory removedAmounts) {
        require(minAmounts.length == TOKEN_COUNT, "CvxTriCrypto2Farm::WrongArrayLength");
        try ICurve3Pool(context.pool).remove_liquidity(lpAmount, _toArray(minAmounts)) {
            address[] memory tokens = _getDexTokens();
            removedAmounts = new uint256[](3);
            for (uint256 i = 0; i < tokens.length; i++) {
                removedAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
            }
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("CvxTriCrypto2Farm::CallRemoveLiquidityFail");
        }
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
