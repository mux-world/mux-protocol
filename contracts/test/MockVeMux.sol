// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

contract MockVeMux {
    mapping(address => uint256) public balanceOf;

    function name() external view returns (string memory) {
        return "veMUX";
    }

    function decimals() external view returns (uint8) {
        return 18;
    }

    function stake(uint256 amount) external {
        balanceOf[msg.sender] = amount;
    }

    function userPointEpoch(address _addr) external view returns (uint256) {
        return 1;
    }

    function userPointHistoryTime(address _addr, uint256 _idx) external view returns (uint256) {
        return 1661385600;
    }

    function balanceOfWhen(address addr, uint256 _t) public view returns (uint256) {
        return balanceOf[addr];
    }
}
