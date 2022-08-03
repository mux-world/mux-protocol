// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../libraries/LibUtils.sol";
import "./SushiFarm.sol";

interface ISpookySwapFarm {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    function boo() external view returns (address);

    function userInfo(uint256, address) external view returns (UserInfo memory);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function pendingBOO(uint256 pid, address userAddress) external view returns (uint256);
}

contract SpookySwapFarm is SushiFarm {
    using SafeERC20 for IERC20;

    function _rewardToken(Context memory context) internal view override returns (address) {
        return ISpookySwapFarm(context.farm).boo();
    }

    function _pendingRewards(Context memory context) internal view override returns (uint256) {
        return ISpookySwapFarm(context.farm).pendingBOO(context.poolId, address(this));
    }
}
