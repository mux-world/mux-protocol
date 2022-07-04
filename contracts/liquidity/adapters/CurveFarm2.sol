// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "./CurveFarm.sol";

interface ICurve2Pool {
    function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external returns (uint256);

    function remove_liquidity(uint256 _burn_amount, uint256[2] memory _min_amounts)
        external
        returns (uint256[2] memory);

    function calc_token_amount(uint256[2] memory _amounts, bool _is_deposit) external view returns (uint256);

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256 dy);
}

/**
 * @notice A module to provide liquidity to curve then farm on some project with the lpToken.
 */
contract CurveFarm2 is CurveFarm {
    uint256 constant TOKEN_COUNT = 2;

    function initializeAdapter(bytes memory initialData) external override {
        Context memory context = abi.decode(initialData, (Context));
        require(context.pool != address(0), "!A0");
        require(context.lpToken != address(0), "!A1");
        require(
            (context.farm == address(0) && context.rewardToken == address(0)) ||
                (context.farm != address(0) && context.rewardToken != address(0)),
            "!A2"
        );
        require(context.quoteIndex < TOKEN_COUNT, "!A3");
        address[] memory tokens = _getDexTokens();
        require(tokens.length == TOKEN_COUNT, "LEN");
        for (uint256 i = 0; i < TOKEN_COUNT; i++) {
            require(tokens[i] == ICurvePool(context.pool).coins(i), "!TK");
        }
        _dexData[_dexId()].config = initialData;
    }

    function _getPrices(Context memory context, uint256 tokenCount)
        internal
        view
        override
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
                try ICurve2Pool(context.pool).get_dy(int128(i), int128(uint128(quoteIndex)), 10**decimals) returns (
                    uint256 dy
                ) {
                    prices[i] = dy;
                } catch Error(string memory reason) {
                    revert(reason);
                } catch {
                    revert("SushiFarm::CallGetPriceFail");
                }
            }
        }
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
        try ICurve2Pool(context.pool).calc_token_amount(_toArray(maxAmounts), true) returns (uint256 _minLpAmount) {
            minLpAmount = _minLpAmount;
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("CurveFarm2::CallCalcTokenAmountFail");
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
        require(maxAmounts.length == TOKEN_COUNT, "CurveFarm2::WrongArrayLength");
        try ICurve2Pool(context.pool).add_liquidity(_toArray(maxAmounts), minLpAmount) returns (uint256 _lpAmount) {
            lpAmount = _lpAmount;
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("CurveFarm2::CallAddLiquidityFail");
        }
    }

    function _removeLiquidity(
        Context memory context,
        uint256 lpAmount,
        uint256[] memory minAmounts
    ) public virtual override returns (uint256[] memory removedAmounts) {
        require(minAmounts.length == TOKEN_COUNT, "CurveFarm2::WrongArrayLength");
        try ICurve2Pool(context.pool).remove_liquidity(lpAmount, _toArray(minAmounts)) returns (
            uint256[TOKEN_COUNT] memory _removedAmounts
        ) {
            removedAmounts = _toSlice(_removedAmounts);
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("CurveFarm2::CallRemoveLiquidityFail");
        }
    }

    function _toArray(uint256[] memory _in) internal pure returns (uint256[TOKEN_COUNT] memory _out) {
        require(_in.length == TOKEN_COUNT, "CurveFarm2::WrongArrayLength");
        _out[0] = _in[0];
        _out[1] = _in[1];
    }

    function _toSlice(uint256[TOKEN_COUNT] memory _in) internal pure returns (uint256[] memory _out) {
        _out = new uint256[](TOKEN_COUNT);
        _out[0] = _in[0];
        _out[1] = _in[1];
    }
}
