// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

abstract contract Bridge {
    function withdraw(
        bytes calldata _wdmsg,
        bytes[] calldata _sigs,
        address[] calldata _signers,
        uint256[] calldata _powers
    ) external virtual;
}
