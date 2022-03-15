// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./Storage.sol";
import "../libraries/LibMuxAdmin.sol";

contract Admin is Storage {
    event SetFundingParams(uint8 tokenId, uint32 newBaseRate8H, uint32 newLimitRate8H);
    event SetFundingInterval(uint32 oldFundingInterval, uint32 newFundingInterval);
    event AddAsset(
        uint8 indexed id,
        bytes32 symbol,
        uint8 decimals,
        bool isStable,
        address tokenAddress,
        address muxTokenAddress
    );
    event SetAssetParams(
        uint8 indexed assetId,
        uint32 newInitialMarginRate,
        uint32 newMaintenanceMarginRate,
        uint32 newPositionFeeRate,
        uint32 newMinProfitRate,
        uint32 newMinProfitTime,
        uint96 newMaxLongPositionSize,
        uint96 newMaxShortPositionSize,
        uint32 newSpotWeight,
        address newBackupOracle,
        uint8 newBackupOracleType
    );
    event SetAssetFlags(bool isTradable, bool isOpenable, bool isShortable, bool useStableTokenForProfit);
    event SetAddresses(
        address oldOrderBook,
        address newOrderBook,
        address oldLiquidityManager,
        address newLiquidityManager
    );
    event SetLiquidityLockPeriod(uint32 oldLockPeriod, uint32 newLockPeriod);
    event TransferLiquidity(address indexed sender, address indexed recipient, uint8 assetId, uint256 amount);

    function setParams(AdminParamsType paramType, bytes calldata params) external {
        if (paramType == AdminParamsType.WithdrawLiquidity || paramType == AdminParamsType.DepositLiquidity) {
            require(_msgSender() == _storage.liquidityManager, "SenderMustBeLM");
        } else {
            require(owner() == _msgSender(), "SenderMustBeOwner");
        }
        LibMuxAdmin.setParams(_storage, paramType, params);
    }
}
