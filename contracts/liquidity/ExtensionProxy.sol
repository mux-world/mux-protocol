// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "./Storage.sol";

interface IExports {
    function exports() external pure returns (bytes4[] memory selectors);
}

// functionCall chain:
// upgradeableProxy(admin) => liquidityManager => module => plugin
contract ExtensionProxy is Storage {
    event PluginCall(address sender, address target, bytes4 sig, bytes payload);

    fallback() external {
        _delegate();
    }

    function _delegate() internal {
        address target = _plugins[msg.sig];
        require(target != address(0), "NPG"); // no plugin
        emit PluginCall(msg.sender, target, msg.sig, msg.data);
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())
            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())
            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
