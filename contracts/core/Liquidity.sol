// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../libraries/LibAsset.sol";
import "../libraries/LibSubAccount.sol";
import "../libraries/LibMath.sol";
import "../interfaces/IMlpTimeLock.sol";

import "./Account.sol";
import "./Storage.sol";

contract Liquidity is Storage, Account {
    using LibAsset for Asset;
    using LibMath for uint256;
    using LibSubAccount for bytes32;

    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint32 mlpFeeRate
    ) external onlyOrderBook {
        require(trader != address(0), "T=0"); // Trader address is zero
        require(_hasAsset(tokenId), "LST"); // the asset is not LiSTed
        require(tokenPrice != 0, "P=0"); // Price Is Zero
        require(mlpPrice != 0, "P=0"); // Price Is Zero
        require(mlpPrice <= _storage.mlpPriceUpperBound, "MPO"); // Mlp Price is Out of range
        require(mlpPrice >= _storage.mlpPriceLowerBound, "MPO"); // Mlp Price is Out of range
        require(mlpFeeRate < 1e5, "F>1");
        // token amount
        Asset storage token = _storage.assets[tokenId];
        uint256 rawAmount = token.calcTransferredBalance();
        require(rawAmount != 0, "A=0"); // Amount Is Zero
        uint96 wadAmount = token.toWad(rawAmount);
        token.spotLiquidity += wadAmount; // already reserved fee
        // fee
        uint96 feeCollateral = uint256(wadAmount).rmul(mlpFeeRate).safeUint96();
        token.collectedFee += feeCollateral;
        emit CollectedFee(tokenId, feeCollateral);
        wadAmount -= feeCollateral;
        // mlp
        uint96 mlpAmount = ((uint256(wadAmount) * uint256(tokenPrice)) / uint256(mlpPrice)).safeUint96();
        IERC20Upgradeable(_storage.mlp).transfer(_storage.mlpTimeLock, mlpAmount);
        IMlpTimeLock(_storage.mlpTimeLock).addMlp(trader, mlpAmount);
        emit AddLiquidity(trader, tokenId, tokenPrice, mlpPrice, mlpAmount, feeCollateral);
    }

    function removeLiquidity(
        address trader,
        uint96 mlpAmount, // NOTE: OrderBook SHOULD transfer mlpAmount to LiquidityPool
        uint8 tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint32 mlpFeeRate
    ) external onlyOrderBook {
        require(trader != address(0), "T=0"); // Trader address is zero
        require(_hasAsset(tokenId), "LST"); // the asset is not LiSTed
        require(tokenPrice != 0, "P=0"); // Price Is Zero
        require(mlpPrice != 0, "P=0"); // Price Is Zero
        require(mlpPrice <= _storage.mlpPriceUpperBound, "MPO"); // Mlp Price is Out of range
        require(mlpPrice >= _storage.mlpPriceLowerBound, "MPO"); // Mlp Price is Out of range
        require(mlpAmount != 0, "A=0"); // Amount Is Zero
        require(mlpFeeRate < 1e5, "F>1");
        // amount
        Asset storage token = _storage.assets[tokenId];
        uint96 wadAmount = ((uint256(mlpAmount) * uint256(mlpPrice)) / uint256(tokenPrice)).safeUint96();
        // fee
        uint96 feeCollateral = uint256(wadAmount).rmul(mlpFeeRate).safeUint96();
        token.collectedFee += feeCollateral;
        emit CollectedFee(tokenId, feeCollateral);
        wadAmount -= feeCollateral;
        // send token
        uint96 spot = LibMath.min(wadAmount, token.spotLiquidity);
        if (spot > 0) {
            token.spotLiquidity -= spot; // already reserved fee
            uint256 rawAmount = token.toRaw(spot);
            token.transferOut(trader, rawAmount, _storage.weth);
        }
        // debt
        uint96 muxTokenAmount = wadAmount - spot;
        if (muxTokenAmount > 0) {
            token.issueMuxToken(trader, uint256(muxTokenAmount));
            emit IssueMuxToken(token.isStable ? 0 : token.id, token.isStable, muxTokenAmount);
        }
        emit RemoveLiquidity(trader, tokenId, tokenPrice, mlpPrice, mlpAmount, feeCollateral);
    }

    /**
     * @notice Broker can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     * @param  stableUtilization    Stable coin utilization
     * @param  unstableTokenIds     All unstable Asset id(s) MUST be passed in order. ex: 1, 2, 5, 6, ...
     * @param  unstableUtilizations Unstable Asset utilizations
     */
    function updateFundingState(
        uint32 stableUtilization, // 1e5
        uint8[] calldata unstableTokenIds,
        uint32[] calldata unstableUtilizations // 1e5
    ) external onlyOrderBook {
        uint32 nextFundingTime = (_blockTimestamp() / _storage.fundingInterval) * _storage.fundingInterval;
        if (_storage.lastFundingTime == 0) {
            // init state
            _updateFundingState(stableUtilization, unstableTokenIds, unstableUtilizations, 0);
        } else if (_storage.lastFundingTime + _storage.fundingInterval >= _blockTimestamp()) {
            // do nothing
        } else {
            uint32 timespan = nextFundingTime - _storage.lastFundingTime;
            _updateFundingState(stableUtilization, unstableTokenIds, unstableUtilizations, timespan);
        }
        _storage.lastFundingTime = nextFundingTime;
    }

    function _updateFundingState(
        uint32 stableUtilization, // 1e5
        uint8[] calldata unstableTokenIds,
        uint32[] calldata unstableUtilizations, // 1e5
        uint32 timespan
    ) internal {
        require(unstableTokenIds.length == unstableUtilizations.length, "LEN"); // LENgth of 2 arguments does not match
        // stable
        {
            (uint32 newFundingRate, uint128 cumulativeFunding) = _getFundingRate(
                _storage.shortFundingBaseRate8H,
                _storage.shortFundingLimitRate8H,
                stableUtilization,
                timespan
            );
            _storage.shortCumulativeFunding += cumulativeFunding;
            emit UpdateFundingRate(0, true, newFundingRate, _storage.shortCumulativeFunding);
        }
        // unstable
        uint8 tokenLen = uint8(_storage.assets.length);
        uint8 i = 0;
        for (uint8 tokenId = 0; tokenId < tokenLen; tokenId++) {
            Asset storage asset = _storage.assets[tokenId];
            if (asset.isStable) {
                continue;
            }
            require(i < unstableTokenIds.length, "LEN"); // invalid LENgth of unstableTokenIds
            require(unstableTokenIds[i] == tokenId, "Aid"); // AssetID mismatched
            (uint32 newFundingRate, uint128 cumulativeFunding) = _getFundingRate(
                asset.longFundingBaseRate8H,
                asset.longFundingLimitRate8H,
                unstableUtilizations[i],
                timespan
            );
            asset.longCumulativeFunding += cumulativeFunding;
            emit UpdateFundingRate(tokenId, false, newFundingRate, asset.longCumulativeFunding);
            i += 1;
        }
    }

    function _getFundingRate(
        uint32 baseRate8H, // 1e5
        uint32 limitRate8H, // 1e5
        uint32 utilization, // 1e5
        uint32 timespan // 1e0
    ) internal pure returns (uint32 newFundingRate, uint128 cumulativeFunding) {
        require(utilization <= 1e5, "U>1"); // %utilization > 100%
        newFundingRate = uint256(utilization).rmul(limitRate8H).safeUint32();
        newFundingRate = LibMath.max32(newFundingRate, baseRate8H);
        cumulativeFunding = ((uint256(newFundingRate) * uint256(timespan) * 1e13) / FUNDING_PERIOD).safeUint128();
    }

    function redeemMuxToken(
        address trader,
        uint8 tokenId,
        uint96 muxTokenAmount // NOTE: OrderBook SHOULD transfer muxTokenAmount to LiquidityPool
    ) external onlyOrderBook {
        require(trader != address(0), "T=0"); // Trader address is zero
        require(_hasAsset(tokenId), "LST"); // the asset is not LiSTed
        require(muxTokenAmount != 0, "A=0"); // Amount Is Zero
        Asset storage token = _storage.assets[tokenId];
        require(token.spotLiquidity >= muxTokenAmount, "Liq"); // insufficent LIQuidity
        uint256 rawAmount = token.toRaw(muxTokenAmount);
        token.spotLiquidity -= muxTokenAmount;
        token.transferOut(trader, rawAmount, _storage.weth);
        emit RedeemMuxToken(trader, tokenId, muxTokenAmount);
    }
}
