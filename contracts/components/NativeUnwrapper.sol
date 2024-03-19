// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IWETH9.sol";
import "../components/SafeOwnable.sol";

/**
 * @dev NativeUnwrapper unwraps WETH and send ETH back to a Trader.
 *
 *      LiquidityPool is upgradable. WBNB can not send to an upgradable contract. So we unwrap
 *      native asset into NativeUnwrapper first.
 */
contract NativeUnwrapper is SafeOwnable {
    IWETH public immutable weth;
    mapping(address => bool) public whitelist; // contract in this whitelist can send ETH to any Trader
    uint256 public savedGasLimit; // note: 0 means use default
    mapping(address => bool) public maintainers;

    event Granted(address indexed core);
    event Revoked(address indexed core);
    event SetMaintainer(address newMaintainer, bool enable);

    constructor(address weth_) SafeOwnable() {
        weth = IWETH(weth_);
    }

    receive() external payable {}

    function addWhiteList(address core) external onlyOwner {
        require(!whitelist[core], "CHG"); // not CHanGed
        whitelist[core] = true;
        emit Granted(core);
    }

    function removeWhiteList(address core) external onlyOwner {
        require(whitelist[core], "CHG"); // not CHanGed
        whitelist[core] = false;
        emit Revoked(core);
    }

    function unwrap(address payable to, uint256 rawAmount) external {
        require(whitelist[msg.sender], "SND"); // SeNDer is not authorized
        require(to != address(0), "TO0"); // TO is 0
        if (rawAmount == 0) {
            return;
        }

        // wrap
        weth.withdraw(rawAmount);

        // send
        uint256 gasLimit = getWithdrawGasLimit();
        (bool success, ) = to.call{ value: rawAmount, gas: gasLimit }("");
        if (success) {
            return;
        }

        // wrap and send WETH
        weth.deposit{ value: rawAmount }();
        weth.transfer(to, rawAmount);
    }

    function getWithdrawGasLimit() public view returns (uint256 gasLimit) {
        gasLimit = savedGasLimit;
        if (gasLimit == 0) {
            return 50_000;
        }
    }

    function setMaintainer(address newMaintainer, bool enable) external onlyOwner {
        maintainers[newMaintainer] = enable;
        emit SetMaintainer(newMaintainer, enable);
    }

    function setGasLimit(uint256 newGasLimit) external {
        require(msg.sender == owner() || maintainers[msg.sender], "must be maintainer or owner");
        savedGasLimit = newGasLimit;
    }
}
