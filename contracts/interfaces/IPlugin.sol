// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

interface IPlugin {
    function name() external view returns (string memory);

    function exports() external view returns (bytes4[] memory);
}
