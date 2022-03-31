// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MlpToken is ERC20 {
    uint128 public constant PRE_MINED_TOKEN_TOTAL_SUPPLY = uint128(10**36);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(_msgSender(), PRE_MINED_TOKEN_TOTAL_SUPPLY);
    }
}
