// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MlpToken is Initializable, ERC20Upgradeable {
    uint128 public constant PRE_MINED_TOKEN_TOTAL_SUPPLY = uint128(10**36);

    function initialize(string memory name_, string memory symbol_) external initializer {
        __ERC20_init(name_, symbol_);
        _mint(_msgSender(), PRE_MINED_TOKEN_TOTAL_SUPPLY);
    }
}
