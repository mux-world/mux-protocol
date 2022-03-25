// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

library LibMath {
    function max(uint96 a, uint96 b) internal pure returns (uint96) {
        return a >= b ? a : b;
    }

    function min(uint96 a, uint96 b) internal pure returns (uint96) {
        return a <= b ? a : b;
    }

    function max32(uint32 a, uint32 b) internal pure returns (uint32) {
        return a >= b ? a : b;
    }

    function min32(uint32 a, uint32 b) internal pure returns (uint32) {
        return a <= b ? a : b;
    }

    function wmul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / 1e18;
    }

    function rmul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / 1e5;
    }

    function wdiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * 1e18) / b;
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    function safeUint32(uint256 n) internal pure returns (uint32) {
        require(n <= type(uint32).max, "O32");
        return uint32(n);
    }

    function safeUint96(uint256 n) internal pure returns (uint96) {
        require(n <= type(uint96).max, "O96");
        return uint96(n);
    }

    function safeUint128(uint256 n) internal pure returns (uint128) {
        require(n <= type(uint128).max, "O12");
        return uint128(n);
    }
}
