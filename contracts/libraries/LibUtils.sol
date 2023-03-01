// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

interface IDecimals {
    function decimals() external view returns (uint8);
}

library LibUtils {
    bytes4 constant SELECTOR_DECIMALS = 0x313ce567;

    function toBytes32(string memory source) internal pure returns (bytes32 result) {
        uint256 size = bytes(source).length;
        require(size > 0 && size <= 32, "RNG"); // out of range
        assembly {
            result := mload(add(source, 32))
        }
    }

    function norm(
        address[] memory tokens_,
        uint256[] memory amounts_
    ) internal view returns (uint256[] memory normAmounts_) {
        require(tokens_.length == amounts_.length, "L!L");
        uint256 n = tokens_.length;
        normAmounts_ = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 decimals;
            try IDecimals(tokens_[i]).decimals() returns (uint8 decimals_) {
                decimals = decimals_;
            } catch {
                decimals = 18;
            }
            normAmounts_[i] = amounts_[i] / (10 ** decimals);
        }
    }
}
