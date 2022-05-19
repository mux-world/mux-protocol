// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface INativeUnwrapper {
    function unwrap(address payable to, uint256 rawAmount) external;
}
