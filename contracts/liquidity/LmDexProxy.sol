// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/IConnector.sol";
import "./LmStorage.sol";

contract LmDexProxy is LmStorage {
    using Address for address;

    event AddLiquidity(uint8 indexed dexId, uint256[] addedAmounts, uint256 liquidityAmount);
    event RemoveLiquidity(uint8 indexed dexId, uint256 shareAmount, uint256[] removedAmounts);

    function _addDexLiquidity(
        uint8 dexId,
        uint256[] calldata maxAmounts,
        uint256 deadline
    ) internal virtual onlyOwner returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(_hasConnector(dexId), "ConnectorNotExists");
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];

        uint256[] memory minAmounts = _getMinAmounts(maxAmounts, connectorConfig.liquiditySlippage);
        bytes memory result = connectorConfig.connector.functionDelegateCall(
            abi.encodeWithSelector(
                IConnector.addDexLiquidity.selector,
                connectorConfig.dexData,
                maxAmounts,
                minAmounts,
                deadline
            )
        );
        (addedAmounts, liquidityAmount) = abi.decode(result, (uint256[], uint256));
        emit AddLiquidity(dexId, addedAmounts, liquidityAmount);
    }

    function _removeDexLiquidity(
        uint8 dexId,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) internal virtual onlyOwner returns (uint256[] memory removedAmounts) {
        require(_hasConnector(dexId), "ConnectorNotExists");
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = connectorConfig.connector.functionDelegateCall(
            abi.encodeWithSelector(
                IConnector.removeDexLiquidity.selector,
                connectorConfig.dexData,
                shareAmount,
                minAmounts,
                deadline
            )
        );
        removedAmounts = abi.decode(result, (uint256[]));
        emit RemoveLiquidity(dexId, shareAmount, removedAmounts);
    }

    function _hasConnector(uint8 dexId) internal view returns (bool) {
        return _dexConnectorConfigs[dexId].connector != address(0);
    }

    function _getDexRewards(uint8 dexId)
        internal
        virtual
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        require(_hasConnector(dexId), "ConnectorNotExists");
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = connectorConfig.connector.functionDelegateCall(
            abi.encodeWithSelector(IConnector.getDexRewards.selector, connectorConfig.dexData)
        );
        (rewardTokens, rewardAmounts) = abi.decode(result, (address[], uint256[]));
    }

    function _getDexFees(uint8 dexId)
        internal
        virtual
        returns (address[] memory feeTokens, uint256[] memory feeAmounts)
    {
        require(_hasConnector(dexId), "ConnectorNotExists");
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = connectorConfig.connector.functionDelegateCall(
            abi.encodeWithSelector(IConnector.getDexFees.selector, connectorConfig.dexData)
        );
        (feeTokens, feeAmounts) = abi.decode(result, (address[], uint256[]));
    }

    function _getDexRedeemableAmounts(uint8 dexId, uint256 shareAmount)
        internal
        virtual
        returns (uint256[] memory amounts)
    {
        require(_hasConnector(dexId), "ConnectorNotExists");
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = connectorConfig.connector.functionDelegateCall(
            abi.encodeWithSelector(IConnector.getDexRedeemableAmounts.selector, connectorConfig.dexData, shareAmount)
        );
        amounts = abi.decode(result, (uint256[]));
    }

    function _getLpBalance(uint8 dexId) internal virtual returns (uint256 amount) {
        require(_hasConnector(dexId), "ConnectorNotExists");
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        bytes memory result = connectorConfig.connector.functionDelegateCall(
            abi.encodeWithSelector(IConnector.getLpBalance.selector, connectorConfig.dexData)
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
            minAmounts[i] = (maxAmounts[i] * slippage) / 1e5;
        }
    }
}
