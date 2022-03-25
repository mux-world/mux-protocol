// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./LmStorage.sol";
import "./LmDexProxy.sol";

contract LmAdmin is LmStorage, LmDexProxy {
    uint32 public constant DEFAULT_LIQUIDITY_SLIPPAGE = 300; // 0.3%

    event AddDex(uint8 indexed dexId, string name, uint32 dexWeight, uint8[] assetIds, uint32[] assetWeightInDex);
    event SetDexWeight(uint8 indexed dexId, uint32 dexWeight);
    event SetConnector(uint8 indexed dexId, address connector, bytes dexContext);
    event SetSlippage(uint8 indexed dexId, uint32 oldSlippage, uint32 newSlippage);
    event SetBridge(uint256 indexed chainId, address bridge, address recipient, bytes extraData);

    function addDexSpotConfiguration(
        string memory name,
        uint32 dexWeight,
        uint8[] calldata assetIds,
        uint32[] calldata assetWeightInDex
    ) external onlyOwner {
        require(_dexSpotConfigs.length <= 256, "Fll"); // the array is FuLL
        require(assetIds.length > 0, "Mty"); // argument array is eMpTY
        require(assetIds.length == assetWeightInDex.length, "Len"); // LENgth of 2 arguments does not match
        uint8 dexId = uint8(_dexSpotConfigs.length);
        _dexSpotConfigs.push(
            DexSpotConfiguration({
                name: name,
                dexId: dexId,
                dexWeight: dexWeight,
                assetIds: assetIds,
                assetWeightInDex: assetWeightInDex
            })
        );
        emit AddDex(dexId, name, dexWeight, assetIds, assetWeightInDex);
    }

    function setDexConnector(
        uint8 dexId,
        address connector,
        bytes memory dexContext
    ) external onlyOwner {
        require(dexId < _dexSpotConfigs.length, "Lst"); // the asset is not LiSTed
        IConnector(connector).validate(dexContext);
        _dexContexts[dexId] = dexContext;
        _dexConnectorConfigs[dexId].connector = connector;
        _dexConnectorConfigs[dexId].liquiditySlippage = DEFAULT_LIQUIDITY_SLIPPAGE;
        emit SetConnector(dexId, connector, dexContext);
    }

    function setBridge(
        uint256 chainId,
        uint8 provider,
        address bridge,
        address recipient,
        bytes memory extraData
    ) external onlyOwner {
        require(chainId != 0, "C=0");
        _bridgeConfigs[chainId] = BridgeConfiguration({
            chainId: chainId,
            bridge: bridge,
            recipient: recipient,
            nonce: 0,
            extraData: extraData,
            provider: BridgeProvider(provider)
        });
        emit SetBridge(chainId, bridge, recipient, extraData);
    }

    function setDexWeight(uint8 dexId, uint32 dexWeight) external onlyOwner {
        require(dexId < _dexSpotConfigs.length, "Lst"); // the asset is not LiSTed
        _dexSpotConfigs[dexId].dexWeight = dexWeight;
        emit SetDexWeight(dexId, dexWeight);
    }

    function setDexSlippage(uint8 dexId, uint32 newLiquiditySlippage) external onlyOwner {
        require(_hasConnector(dexId), "Lst"); // the asset is not LiSTed
        require(newLiquiditySlippage < 100000, "S>1");

        DexConnectorConfiguration storage connectorConfig = _dexConnectorConfigs[dexId];
        emit SetSlippage(dexId, connectorConfig.liquiditySlippage, newLiquiditySlippage);
        connectorConfig.liquiditySlippage = newLiquiditySlippage;
    }
}
