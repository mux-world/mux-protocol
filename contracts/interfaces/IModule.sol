// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IModule {
    function id() external pure returns (bytes32);

    function meta()
        external
        pure
        returns (
            bytes32[] memory methodIds,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        );
}
