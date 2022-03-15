// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./LmStorage.sol";
import "./LmDexProxy.sol";

contract LmAdmin is LmStorage, LmDexProxy {
    uint256 public constant DEFAULT_LIQUIDITY_SLIPPAGE = 100; // 0.1%

    event AddDex(uint8 indexed dexId, uint32 dexWeight, uint8[] assetIds, uint32[] assetWeightInDex);
    event SetDexWeight(uint8 indexed dexId, uint32 dexWeight);
    event SetConnector(uint8 indexed dexId, address connector, bytes dexData);
    event SetSlippage(uint8 indexed dexId, uint32 oldSlippage, uint32 newSlippage);

    function addDexSpotConfiguration(
        uint32 dexWeight,
        uint8[] calldata assetIds,
        uint32[] calldata assetWeightInDex
    ) external onlyOwner {
        require(_dexSpotConfigs.length <= 256, "DexConfigFull");
        uint8 dexId = uint8(_dexSpotConfigs.length);
        _dexSpotConfigs.push(
            DexSpotConfiguration({
                dexId: dexId,
                dexWeight: dexWeight,
                assetIds: assetIds,
                assetWeightInDex: assetWeightInDex,
                lpToken: address(0)
            })
        );
        emit AddDex(dexId, dexWeight, assetIds, assetWeightInDex);
    }

    function setDexConnector(
        uint8 dexId,
        address connector,
        bytes memory dexData
    ) external onlyOwner {
        require(_dexSpotConfigs[dexId].dexId == dexId, "DexNotExists");

        IConnector _connector = IConnector(connector);
        _connector.validate(dexData);
        _dexSpotConfigs[dexId].lpToken = _connector.getLpToken(dexData);

        _dexConnectorConfigs[dexId].connector = connector;
        _dexConnectorConfigs[dexId].dexData = dexData;

        emit SetConnector(dexId, connector, dexData);
    }

    function setDexWeight(uint8 dexId, uint32 dexWeight) external onlyOwner {
        require(_dexSpotConfigs[dexId].dexId == dexId, "DexNotExists");
        _dexSpotConfigs[dexId].dexWeight = dexWeight;
        emit SetDexWeight(dexId, dexWeight);
    }

    function setDexSlippage(uint8 dexId, uint32 newLiquiditySlippage) external onlyOwner {
        require(_hasConnector(dexId), "ConnectorNotExists");
        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        emit SetSlippage(dexId, connectorConfig.liquiditySlippage, newLiquiditySlippage);
        connectorConfig.liquiditySlippage = newLiquiditySlippage;
    }

    function _getAssetAddress(uint8 assetId) internal returns (address) {
        if (_tokenCache[assetId] == address(0)) {
            _tokenCache[assetId] = _pool.getAssetAddress(assetId);
        }
        return _tokenCache[assetId];
    }
}
