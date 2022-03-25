// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/IConnector.sol";
import "./LmStorage.sol";
import "./LmTransfer.sol";

contract LmDexProxy is LmStorage, LmTransfer {
    using AddressUpgradeable for address;

    function _hasConnector(uint8 dexId) internal view returns (bool) {
        return _dexConnectorConfigs[dexId].connector != address(0);
    }

    function _addDexLiquidity(
        uint8 dexId,
        uint256[] calldata maxAmounts,
        uint256 deadline
    ) internal virtual returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(_hasConnector(dexId), "Lst"); // the connector is not LiSTed
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];

        uint256[] memory minAmounts = _getMinAmounts(maxAmounts, connectorConfig.liquiditySlippage);
        bytes memory result = _functionDelegateCall(
            connectorConfig.connector,
            abi.encodeWithSelector(
                IConnector.addDexLiquidity.selector,
                _dexContexts[dexId],
                maxAmounts,
                minAmounts,
                deadline
            )
        );
        uint256[] memory feeAmounts;
        (_dexContexts[dexId], addedAmounts, liquidityAmount, feeAmounts) = abi.decode(
            result,
            (bytes, uint256[], uint256, uint256[])
        );
        _transferTo(_vault, _dexSpotConfigs[dexId].assetIds, feeAmounts);
    }

    function _removeDexLiquidity(
        uint8 dexId,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) internal virtual returns (uint256[] memory removedAmounts) {
        require(_hasConnector(dexId), "Lst"); // the connector is not LiSTed
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = _functionDelegateCall(
            connectorConfig.connector,
            abi.encodeWithSelector(
                IConnector.removeDexLiquidity.selector,
                _dexContexts[dexId],
                shareAmount,
                minAmounts,
                deadline
            )
        );
        uint256[] memory feeAmounts;
        (_dexContexts[dexId], removedAmounts, feeAmounts) = abi.decode(result, (bytes, uint256[], uint256[]));
        _transferTo(_vault, _dexSpotConfigs[dexId].assetIds, feeAmounts);
    }

    function _claimDexRewards(uint8 dexId)
        internal
        virtual
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        require(_hasConnector(dexId), "Lst"); // the connector is not LiSTed
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = _functionDelegateCall(
            connectorConfig.connector,
            abi.encodeWithSelector(IConnector.claimDexRewards.selector, _dexContexts[dexId])
        );
        (rewardTokens, rewardAmounts) = abi.decode(result, (address[], uint256[]));
        _transferTo(_vault, rewardTokens, rewardAmounts);
    }

    function _getDexRewards(uint8 dexId)
        internal
        virtual
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        require(_hasConnector(dexId), "Lst"); // the connector is not LiSTed
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = _functionDelegateCall(
            connectorConfig.connector,
            abi.encodeWithSelector(IConnector.getDexRewards.selector, _dexContexts[dexId])
        );
        (rewardTokens, rewardAmounts) = abi.decode(result, (address[], uint256[]));
    }

    function _getDexFees(uint8 dexId) internal virtual returns (uint256[] memory feeAmounts) {
        require(_hasConnector(dexId), "Lst"); // the connector is not LiSTed
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = _functionDelegateCall(
            connectorConfig.connector,
            abi.encodeWithSelector(IConnector.getDexFees.selector, _dexContexts[dexId])
        );
        feeAmounts = abi.decode(result, (uint256[]));
    }

    function _getDexRedeemableAmounts(uint8 dexId, uint256 shareAmount)
        internal
        virtual
        returns (uint256[] memory amounts)
    {
        require(_hasConnector(dexId), "Lst"); // the connector is not LiSTed
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = _functionDelegateCall(
            connectorConfig.connector,
            abi.encodeWithSelector(IConnector.getDexRedeemableAmounts.selector, _dexContexts[dexId], shareAmount)
        );
        amounts = abi.decode(result, (uint256[]));
    }

    function _getLpBalance(uint8 dexId) internal virtual returns (uint256 amount) {
        require(_hasConnector(dexId), "Lst"); // the connector is not LiSTed
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = _functionDelegateCall(
            connectorConfig.connector,
            abi.encodeWithSelector(IConnector.getLpBalance.selector, _dexContexts[dexId])
        );
        amount = abi.decode(result, (uint256));
    }

    function _getMinAmounts(uint256[] memory maxAmounts, uint32 slippage)
        internal
        pure
        returns (uint256[] memory minAmounts)
    {
        uint256 length = maxAmounts.length;
        minAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            minAmounts[i] = (maxAmounts[i] * (100000 - slippage)) / 1e5;
        }
    }

    function _functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        require(target.isContract(), "T!C");
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return AddressUpgradeable.verifyCallResult(success, returndata, "!DC");
    }
}
