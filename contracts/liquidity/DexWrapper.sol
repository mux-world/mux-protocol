// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/IDexAdapter.sol";
import "./AssetManager.sol";

contract DexWrapper is AssetManager {
    using AddressUpgradeable for address;

    uint256 constant BASE_RATE = 100000;

    event AddDexLiquidity(uint8 dexId, uint256[] maxAmounts, uint256[] addedAmounts, uint256 lpAmount, bytes extraData);
    event RemoveDexLiquidity(uint8 dexId, uint256 shareAmount, uint256[] minAmounts, uint256 deadline);
    event ClaimDexFees(uint8 dexId);

    /**
     * @notice Set dex id before dex method access.
     */
    modifier dexCall(uint8 dexId) {
        require(dexId != 0, "ZDI"); // zero dex id
        uint8 lastDexId = _dexContext.dexId;
        if (lastDexId == 0) {
            _dexContext.dexId = dexId;
        } else {
            require(lastDexId == dexId, "NDR"); // no dex-call reentrant
        }
        _;
        _dexContext.dexId = lastDexId;
    }

    // read methods
    function getDexLpBalance(uint8 dexId) public dexCall(dexId) returns (uint256 lpBalance) {
        DexRegistration storage registration = _dexAdapters[dexId];
        if (_dexAdapters[dexId].adapter != address(0)) {
            bytes memory returnData = _delegateCall(
                registration.adapter,
                abi.encodeWithSelector(IDexAdapter.getLpBalance.selector)
            );
            lpBalance = abi.decode(returnData, (uint256));
        } else {
            lpBalance = 0;
        }
    }

    function getDexFees(uint8 dexId)
        external
        dexCall(dexId)
        returns (
            address[] memory tokens,
            uint256[] memory claimedAmounts,
            uint256[] memory pendingAmounts
        )
    {
        DexRegistration storage registration = _dexAdapters[dexId];
        if (_dexAdapters[dexId].adapter != address(0)) {
            bytes memory returnData = _delegateCall(
                registration.adapter,
                abi.encodeWithSelector(IDexAdapter.getFees.selector)
            );
            (tokens, claimedAmounts, pendingAmounts) = abi.decode(returnData, (address[], uint256[], uint256[]));
        } else {
            uint256 n = _dexSpotConfigs[dexId].assetIds.length;
            tokens = new address[](n);
            claimedAmounts = _makeEmpty(n);
            pendingAmounts = _makeEmpty(n);
        }
    }

    function getDexSpotAmounts(uint8 dexId, uint256 shareAmount)
        public
        dexCall(dexId)
        returns (uint256[] memory amounts)
    {
        DexRegistration storage registration = _dexAdapters[dexId];
        if (_dexAdapters[dexId].adapter != address(0)) {
            bytes memory returnData = _delegateCall(
                registration.adapter,
                abi.encodeWithSelector(IDexAdapter.getSpotAmounts.selector, shareAmount)
            );
            amounts = abi.decode(returnData, (uint256[]));
        } else {
            uint256 n = _dexSpotConfigs[dexId].assetIds.length;
            amounts = _makeEmpty(n);
        }
    }

    function getDexTotalSpotAmounts(uint8 dexId) public dexCall(dexId) returns (uint256[] memory amounts) {
        DexRegistration storage registration = _dexAdapters[dexId];
        if (_dexAdapters[dexId].adapter != address(0)) {
            bytes memory returnData = _delegateCall(
                registration.adapter,
                abi.encodeWithSelector(IDexAdapter.getTotalSpotAmounts.selector)
            );
            amounts = abi.decode(returnData, (uint256[]));
        }
    }

    function getDexLiquidityData(uint8 dexId, uint256[] memory amounts)
        external
        dexCall(dexId)
        returns (bytes memory data)
    {
        DexRegistration storage registration = _dexAdapters[dexId];
        if (_dexAdapters[dexId].adapter != address(0)) {
            data = _delegateCall(registration.adapter, abi.encodeWithSignature("getLiquidityData(uint256[])", amounts));
        }
    }

    // write methods
    function addDexLiquidityUniSwapV2(
        uint8 dexId,
        uint256[] calldata amounts,
        uint256 deadline
    ) external dexCall(dexId) auth returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        DexRegistration storage registration = _dexAdapters[dexId];
        require(!registration.disabled, "FRZ");
        require(registration.adapter != address(0), "ANS"); // adapter not set
        _fetchAssets(_dexSpotConfigs[dexId].assetIds, amounts);
        uint256[] memory minAmounts = new uint256[](amounts.length);
        uint256 rate = BASE_RATE - registration.slippage;
        minAmounts[0] = (amounts[0] * rate) / BASE_RATE;
        minAmounts[1] = (amounts[1] * rate) / BASE_RATE;
        bytes memory returnData = _delegateCall(
            registration.adapter,
            abi.encodeWithSelector(IDexAdapter.addLiquidityUniSwapV2.selector, amounts, minAmounts, deadline)
        );
        (addedAmounts, liquidityAmount) = abi.decode(returnData, (uint256[], uint256));
        _repayAssets(dexId, amounts, addedAmounts);

        emit AddDexLiquidity(dexId, amounts, addedAmounts, liquidityAmount, abi.encode(minAmounts, deadline));
    }

    // write methods
    function addDexLiquidityCurve(
        uint8 dexId,
        uint256[] calldata maxAmounts,
        uint256 desiredAmount
    ) external dexCall(dexId) auth returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        DexRegistration storage registration = _dexAdapters[dexId];
        require(!registration.disabled, "FRZ");
        require(registration.adapter != address(0), "ANS"); // adapter not set
        _fetchAssets(_dexSpotConfigs[dexId].assetIds, maxAmounts);
        uint256 minLpAmount = (desiredAmount * (BASE_RATE - registration.slippage)) / BASE_RATE;
        bytes memory returnData = _delegateCall(
            registration.adapter,
            abi.encodeWithSelector(IDexAdapter.addLiquidityCurve.selector, maxAmounts, minLpAmount)
        );
        (addedAmounts, liquidityAmount) = abi.decode(returnData, (uint256[], uint256));

        emit AddDexLiquidity(dexId, maxAmounts, addedAmounts, liquidityAmount, abi.encode(desiredAmount, minLpAmount));
    }

    function removeDexLiquidity(
        uint8 dexId,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external dexCall(dexId) auth returns (uint256[] memory removedAmounts) {
        DexRegistration storage registration = _dexAdapters[dexId];
        require(!registration.disabled, "FRZ");
        require(registration.adapter != address(0), "ANS"); // adapter not set

        bytes memory returnData = _delegateCall(
            registration.adapter,
            abi.encodeWithSelector(IDexAdapter.removeLiquidity.selector, shareAmount, minAmounts, deadline)
        );
        removedAmounts = abi.decode(returnData, (uint256[]));
        if (removedAmounts.length != 0) {
            _pushAssets(_dexSpotConfigs[dexId].assetIds, removedAmounts);
        }
        emit RemoveDexLiquidity(dexId, shareAmount, minAmounts, deadline);
    }

    function claimDexFees(uint8 dexId) external dexCall(dexId) {
        DexRegistration storage registration = _dexAdapters[dexId];
        require(registration.adapter != address(0), "ANS"); // adapter not set
        _delegateCall(registration.adapter, abi.encodeWithSelector(IDexAdapter.claimFees.selector, dexId));
    }

    function _initializeAdapter(uint8 dexId, bytes memory initialData) internal dexCall(dexId) {
        DexRegistration storage registration = _dexAdapters[dexId];
        require(registration.adapter != address(0), "ANS"); // adapter not set
        _delegateCall(
            registration.adapter,
            abi.encodeWithSelector(IDexAdapter.initializeAdapter.selector, initialData)
        );
        emit ClaimDexFees(dexId);
    }

    // helpers
    function _makeEmpty(uint256 length) internal pure returns (uint256[] memory empty) {
        empty = new uint256[](length);
    }

    function _delegateCall(address target, bytes memory callData) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = target.delegatecall(callData);
        return AddressUpgradeable.verifyCallResult(success, returnData, "!DC");
    }
}
