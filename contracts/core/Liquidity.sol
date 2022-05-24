// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../libraries/LibAsset.sol";
import "../libraries/LibSubAccount.sol";
import "../libraries/LibMath.sol";

import "./Account.sol";
import "./Storage.sol";

contract Liquidity is Storage, Account {
    using LibAsset for Asset;
    using LibMath for uint256;
    using LibSubAccount for bytes32;

    /**
     * @dev   Add liquidity
     *
     * @param trader            liquidity provider address
     * @param tokenId           asset.id that added
     * @param rawAmount         asset token amount. decimals = erc20.decimals
     * @param tokenPrice        token price
     * @param mlpPrice          mlp price
     * @param currentAssetValue liquidity USD value of a single asset in all chains (even if tokenId is a stable asset)
     * @param targetAssetValue  weight / Σ weight * total liquidity USD value in all chains
     */
    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint256 rawAmount, // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue
    ) external onlyOrderBook updateSequence {
        require(trader != address(0), "T=0"); // Trader address is zero
        require(_hasAsset(tokenId), "LST"); // the asset is not LiSTed
        require(rawAmount != 0, "A=0"); // Amount Is Zero
        require(mlpPrice != 0, "P=0"); // Price Is Zero
        require(mlpPrice <= _storage.mlpPriceUpperBound, "MPO"); // Mlp Price is Out of range
        require(mlpPrice >= _storage.mlpPriceLowerBound, "MPO"); // Mlp Price is Out of range
        Asset storage token = _storage.assets[tokenId];
        tokenPrice = LibReferenceOracle.checkPrice(token, tokenPrice);

        // token amount
        require(token.isEnabled, "ENA"); // the token is temporarily not ENAbled
        uint96 wadAmount = token.toWad(rawAmount);
        token.spotLiquidity += wadAmount; // already reserved fee
        // fee
        uint32 mlpFeeRate = _getLiquidityFeeRate(
            currentAssetValue,
            targetAssetValue,
            true,
            uint256(wadAmount).wmul(tokenPrice).safeUint96(),
            _storage.liquidityBaseFeeRate,
            _storage.liquidityDynamicFeeRate
        );
        uint96 feeCollateral = uint256(wadAmount).rmul(mlpFeeRate).safeUint96();
        token.collectedFee += feeCollateral; // spotLiquidity was modified above
        emit CollectedFee(tokenId, feeCollateral);
        wadAmount -= feeCollateral;
        // mlp
        uint96 mlpAmount = ((uint256(wadAmount) * uint256(tokenPrice)) / uint256(mlpPrice)).safeUint96();
        IERC20Upgradeable(_storage.mlp).transfer(trader, mlpAmount);
        emit AddLiquidity(trader, tokenId, tokenPrice, mlpPrice, mlpAmount, feeCollateral);
    }

    /**
     * @dev   Remove liquidity
     *
     * @param trader            liquidity provider address
     * @param mlpAmount         mlp amount
     * @param tokenId           asset.id that removed to
     * @param tokenPrice        token price
     * @param mlpPrice          mlp price
     * @param currentAssetValue liquidity USD value of a single asset in all chains (even if tokenId is a stable asset)
     * @param targetAssetValue  weight / Σ weight * total liquidity USD value in all chains
     */
    function removeLiquidity(
        address trader,
        uint96 mlpAmount, // NOTE: OrderBook SHOULD transfer mlpAmount mlp to LiquidityPool
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue
    ) external onlyOrderBook updateSequence {
        require(trader != address(0), "T=0"); // Trader address is zero
        require(_hasAsset(tokenId), "LST"); // the asset is not LiSTed
        require(mlpPrice != 0, "P=0"); // Price Is Zero
        require(mlpPrice <= _storage.mlpPriceUpperBound, "MPO"); // Mlp Price is Out of range
        require(mlpPrice >= _storage.mlpPriceLowerBound, "MPO"); // Mlp Price is Out of range
        require(mlpAmount != 0, "A=0"); // Amount Is Zero
        Asset storage token = _storage.assets[tokenId];
        tokenPrice = LibReferenceOracle.checkPrice(token, tokenPrice);

        // amount
        require(token.isEnabled, "ENA"); // the token is temporarily not ENAbled
        uint96 wadAmount = ((uint256(mlpAmount) * uint256(mlpPrice)) / uint256(tokenPrice)).safeUint96();
        // fee
        uint96 feeCollateral;
        {
            uint32 mlpFeeRate = _getLiquidityFeeRate(
                currentAssetValue,
                targetAssetValue,
                false,
                uint256(wadAmount).wmul(tokenPrice).safeUint96(),
                _storage.liquidityBaseFeeRate,
                _storage.liquidityDynamicFeeRate
            );
            feeCollateral = uint256(wadAmount).rmul(mlpFeeRate).safeUint96();
        }
        token.collectedFee += feeCollateral; // spotLiquidity will be modified below
        emit CollectedFee(tokenId, feeCollateral);
        wadAmount -= feeCollateral;
        // send token
        require(wadAmount <= token.spotLiquidity, "LIQ"); // insufficient LIQuidity
        token.spotLiquidity -= wadAmount; // already deduct fee
        uint256 rawAmount = token.toRaw(wadAmount);
        token.transferOut(trader, rawAmount, _storage.weth, _storage.nativeUnwrapper);
        emit RemoveLiquidity(trader, tokenId, tokenPrice, mlpPrice, mlpAmount, feeCollateral);
    }

    /**
     * @notice Redeem mux token into original tokens
     *
     *         Only strict stable coins and un-stable coins are supported.
     */
    function redeemMuxToken(
        address trader,
        uint8 tokenId,
        uint96 muxTokenAmount // NOTE: OrderBook SHOULD transfer muxTokenAmount to LiquidityPool
    ) external onlyOrderBook updateSequence {
        require(trader != address(0), "T=0"); // Trader address is zero
        require(_hasAsset(tokenId), "LST"); // the asset is not LiSTed
        require(muxTokenAmount != 0, "A=0"); // Amount Is Zero
        Asset storage token = _storage.assets[tokenId];
        require(token.isEnabled, "ENA"); // the token is temporarily not ENAbled
        if (token.isStable) {
            require(token.isStrictStable, "STR"); // only STRict stable coins and un-stable coins are supported
        }
        require(token.spotLiquidity >= muxTokenAmount, "LIQ"); // insufficient LIQuidity
        uint256 rawAmount = token.toRaw(muxTokenAmount);
        token.spotLiquidity -= muxTokenAmount;
        token.transferOut(trader, rawAmount, _storage.weth, _storage.nativeUnwrapper);
        emit RedeemMuxToken(trader, tokenId, muxTokenAmount);
    }

    /**
     * @notice Broker can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     *         Check _getFundingRate in Liquidity.sol on how to calculate funding rate.
     * @param  stableUtilization    Stable coin utilization in all chains
     * @param  unstableTokenIds     All unstable Asset id(s) MUST be passed in order. ex: 1, 2, 5, 6, ...
     * @param  unstableUtilizations Unstable Asset utilizations in all chains
     * @param  unstablePrices       Unstable Asset prices
     */
    function updateFundingState(
        uint32 stableUtilization, // 1e5
        uint8[] calldata unstableTokenIds,
        uint32[] calldata unstableUtilizations, // 1e5
        uint96[] calldata unstablePrices
    ) external onlyOrderBook updateSequence {
        uint32 nextFundingTime = (_blockTimestamp() / _storage.fundingInterval) * _storage.fundingInterval;
        if (_storage.lastFundingTime == 0) {
            // init state. just update lastFundingTime
            _storage.lastFundingTime = nextFundingTime;
        } else if (_storage.lastFundingTime + _storage.fundingInterval >= _blockTimestamp()) {
            // do nothing
        } else {
            uint32 timeSpan = nextFundingTime - _storage.lastFundingTime;
            _updateFundingState(stableUtilization, unstableTokenIds, unstableUtilizations, unstablePrices, timeSpan);
            _storage.lastFundingTime = nextFundingTime;
        }
    }

    function _updateFundingState(
        uint32 stableUtilization, // 1e5
        uint8[] calldata unstableTokenIds,
        uint32[] calldata unstableUtilizations, // 1e5
        uint96[] calldata unstablePrices,
        uint32 timeSpan
    ) internal {
        require(unstableTokenIds.length == unstableUtilizations.length, "LEN"); // LENgth of 2 arguments does not match
        require(unstableTokenIds.length == unstablePrices.length, "LEN"); // LENgth of 2 arguments does not match
        // stable
        uint32 shortFundingRate;
        uint128 shortCumulativeFundingRate;
        (shortFundingRate, shortCumulativeFundingRate) = _getFundingRate(
            _storage.shortFundingBaseRate8H,
            _storage.shortFundingLimitRate8H,
            stableUtilization,
            timeSpan
        );
        // unstable
        uint8 tokenLen = uint8(_storage.assets.length);
        uint8 i = 0;
        for (uint8 tokenId = 0; tokenId < tokenLen; tokenId++) {
            Asset storage asset = _storage.assets[tokenId];
            if (asset.isStable) {
                continue;
            }
            require(i < unstableTokenIds.length, "LEN"); // invalid LENgth of unstableTokenIds
            require(unstableTokenIds[i] == tokenId, "AID"); // AssetID mismatched
            (uint32 longFundingRate, uint128 longCumulativeFundingRate) = _getFundingRate(
                asset.longFundingBaseRate8H,
                asset.longFundingLimitRate8H,
                unstableUtilizations[i],
                timeSpan
            );
            asset.longCumulativeFundingRate += longCumulativeFundingRate;
            {
                uint96 price = LibReferenceOracle.checkPrice(asset, unstablePrices[i]);
                asset.shortCumulativeFunding += uint256(shortCumulativeFundingRate).wmul(price).safeUint128();
            }
            emit UpdateFundingRate(
                tokenId,
                longFundingRate,
                asset.longCumulativeFundingRate,
                shortFundingRate,
                asset.shortCumulativeFunding
            );
            i += 1;
        }
    }

    /**
     * @dev   Liquidity fee rate
     *
     *        Lower rates indicate liquidity is closer to target.
     *
     *                                                  targetLiquidity
     *                     <------------------------------------+--------------------------------------> liquidity
     *
     * case 1: high rebate   * currentLiq * newLiq
     *                       * currentLiq                                                    * newLiq
     *
     * case 2: low rebate                 * currentLiq * newLiq
     *                                    * currentLiq                          * newLiq
     *
     * case 3: higher fee                                          * currentLiq * newLiq
     *
     * case 4: max fee                                             * currentLiq              * newLiq
     *                                                                          * currentLiq * newLiq
     *
     * @param currentAssetValue liquidity USD value of a single asset in all chains (even if tokenId is a stable asset)
     * @param targetAssetValue  weight / Σ weight * total liquidity USD value in all chains
     * @param isAdd             true if add liquidity, false if remove liquidity
     * @param deltaValue        add/remove liquidity USD value
     * @param baseFeeRate       base fee
     * @param dynamicFeeRate    dynamic fee
     */
    function _getLiquidityFeeRate(
        uint96 currentAssetValue,
        uint96 targetAssetValue,
        bool isAdd,
        uint96 deltaValue,
        uint32 baseFeeRate, // 1e5
        uint32 dynamicFeeRate // 1e5
    ) internal pure returns (uint32) {
        uint96 newAssetValue;
        if (isAdd) {
            newAssetValue = currentAssetValue + deltaValue;
        } else {
            require(currentAssetValue >= deltaValue, "LIQ"); // insufficient LIQuidity
            newAssetValue = currentAssetValue - deltaValue;
        }
        // | x - target |
        uint96 oldDiff = currentAssetValue > targetAssetValue
            ? currentAssetValue - targetAssetValue
            : targetAssetValue - currentAssetValue;
        uint96 newDiff = newAssetValue > targetAssetValue
            ? newAssetValue - targetAssetValue
            : targetAssetValue - newAssetValue;
        if (targetAssetValue == 0) {
            // avoid division by 0
            return baseFeeRate;
        } else if (newDiff < oldDiff) {
            // improves
            uint32 rebate = ((uint256(dynamicFeeRate) * uint256(oldDiff)) / uint256(targetAssetValue)).safeUint32();
            return baseFeeRate > rebate ? baseFeeRate - rebate : 0;
        } else {
            // worsen
            uint96 avgDiff = (oldDiff + newDiff) / 2;
            avgDiff = LibMath.min(avgDiff, targetAssetValue);
            uint32 dynamic = ((uint256(dynamicFeeRate) * uint256(avgDiff)) / uint256(targetAssetValue)).safeUint32();
            return baseFeeRate + dynamic;
        }
    }

    /**
     * @dev Funding rate formula
     *
     * ^ fr           / limit
     * |            /
     * |          /
     * |        /
     * |______/ base
     * |    .
     * |  .
     * |.
     * +-------------------> %util
     */
    function _getFundingRate(
        uint32 baseRate8H, // 1e5
        uint32 limitRate8H, // 1e5
        uint32 utilization, // 1e5
        uint32 timeSpan // 1e0
    ) internal pure returns (uint32 newFundingRate, uint128 cumulativeFundingRate) {
        require(utilization <= 1e5, "U>1"); // %utilization > 100%
        newFundingRate = uint256(utilization).rmul(limitRate8H).safeUint32();
        newFundingRate = LibMath.max32(newFundingRate, baseRate8H);
        cumulativeFundingRate = ((uint256(newFundingRate) * uint256(timeSpan) * 1e13) / FUNDING_PERIOD).safeUint128();
    }
}
