// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../libraries/LibUtils.sol";
import "./SushiFarm.sol";

interface ITraderJoeFarm {
    struct UserInfo {
        uint256 amount; // LP tokens provided
        uint256 rewardDebt; // pending reward = user.amount * pool.accRewardPerShare - user.rewardDebt
    }

    function JOE() external view returns (address);

    function userInfo(uint256, address) external view returns (UserInfo memory);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingJoe,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        );
}

contract TraderJoeFarm is SushiFarm {
    using SafeERC20 for IERC20;

    function _rewardToken(Context memory context) internal view override returns (address) {
        return ITraderJoeFarm(context.farm).JOE();
    }

    function _pendingRewards(Context memory context) internal view override returns (uint256) {
        (uint256 pendingJoe, , , ) = ITraderJoeFarm(context.farm).pendingTokens(context.poolId, address(this));
        return pendingJoe;
    }
}
