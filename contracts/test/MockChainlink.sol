// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

contract MockChainlink {
    int256 _answer;

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestAnswer() external view returns (int256) {
        return _answer;
    }

    function setAnswer(int256 answer) external {
        _answer = answer;
    }
}
