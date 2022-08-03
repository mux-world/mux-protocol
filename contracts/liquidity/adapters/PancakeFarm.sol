// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../libraries/LibUtils.sol";
import "./SushiFarm.sol";

interface IPancakeFarm {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    function CAKE() external view returns (address);

    function userInfo(uint256, address) external view returns (UserInfo memory);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function pendingCake(uint256 pid, address userAddress) external view returns (uint256);
}

contract PancakeFarm is SushiFarm {
    using SafeERC20 for IERC20;

    function _rewardToken(Context memory context) internal view override returns (address) {
        return IPancakeFarm(context.farm).CAKE();
    }

    function _pendingRewards(Context memory context) internal view override returns (uint256) {
        return IPancakeFarm(context.farm).pendingCake(context.poolId, address(this));
    }
}
