// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../libraries/LibUtils.sol";
import "./DexModule.sol";

/**
 * @notice A module to provide liquidity to uniswap-v2-like dex then farm on some project with the lpToken.
 */
contract UniFarmRewardModule is DexModule {
    using Address for address;
    using SafeERC20 for IERC20;

    address public immutable rewardToken;
    address public immutable stake;
    uint256 public immutable poolId;

    constructor(
        address rewardToken_,
        address stake_,
        uint256 poolId_
    ) {
        rewardToken = rewardToken_;
        stake = stake_;
        poolId = poolId_;
    }

    function id() public pure override returns (bytes32) {
        return LibUtils.toBytes32("pc-demo-farm-reward-mod");
    }

    function meta()
        public
        pure
        override
        returns (
            bytes32[] memory ids,
            bytes4[] memory selectors,
            bytes32[] memory initialStates
        )
    {
        ids = new bytes32[](2);
        ids[0] = LibUtils.toBytes32("getReward");
        ids[1] = LibUtils.toBytes32("claimReward");
        selectors = new bytes4[](2);
        selectors[0] = this.getReward.selector;
        selectors[1] = this.claimReward.selector;
        initialStates = new bytes32[](0);
    }

    function tokens() public view override returns (bool needCheck, address[] memory tokens_) {}

    function getReward() public view returns (uint256) {
        return IStake(stake).pendingReward(poolId, address(this));
    }

    function claimReward() public view returns (uint256[] memory feeAmounts) {}
}

interface IStake {
    struct UserInfo {
        uint256 amount; // LP tokens provided
        uint256 rewardDebt; // pending reward = user.amount * pool.accRewardPerShare - user.rewardDebt
    }

    function userInfo(uint256, address) external view returns (UserInfo memory);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function rewardToken() external view returns (uint256);

    function pendingReward(uint256 pid, address userAddress) external view returns (uint256);
}
