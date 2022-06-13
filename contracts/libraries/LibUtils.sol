// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

library LibUtils {
    function toBytes32(string memory source) internal pure returns (bytes32 result) {
        uint256 size = bytes(source).length;
        require(size > 0 && size <= 32, "RNG"); // out of range
        assembly {
            result := mload(add(source, 32))
        }
    }

    // function toAddress(bytes32 val) internal pure returns (address) {
    //     return address(bytes20(val));
    // }

    // function toBytes32(address val) internal pure returns (bytes32) {
    //     return bytes32(bytes20(val));
    // }
}
