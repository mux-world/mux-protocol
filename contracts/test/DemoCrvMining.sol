// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DemoCrvMining {
    address public lp;
    address public rewardToken;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public updateTimes;
    mapping(address => mapping(address => uint256)) public pendingRewards;

    constructor(address lp_, address rewardToken_) {
        lp = lp_;
        rewardToken = rewardToken_;
    }

    function deposit(
        uint256 _value,
        address _user,
        bool _claim_rewards
    ) external {
        IERC20(lp).transferFrom(msg.sender, address(this), _value);
        _update(_user);
        balanceOf[_user] += _value;
        totalSupply += _value;
        if (_claim_rewards) {
            claim_rewards(_user, _user);
        }
    }

    function withdraw(
        uint256 _value,
        address _user,
        bool _claim_rewards
    ) external {
        _update(_user);
        balanceOf[_user] -= _value;
        totalSupply -= _value;
        IERC20(lp).transfer(msg.sender, _value);
        if (_claim_rewards) {
            claim_rewards(_user, _user);
        }
    }

    function _update(address _user) internal {
        pendingRewards[_user][address(this)] += (block.timestamp - updateTimes[_user]) * balanceOf[_user];
        updateTimes[_user] = block.timestamp;
    }

    function claimable_reward(address _user, address _token) external view returns (uint256) {
        return pendingRewards[_user][_token];
    }

    function claim_rewards(address _addr, address _receiver) public {
        _update(_addr);
        uint256 r = pendingRewards[_addr][address(this)];
        pendingRewards[_addr][address(this)] = 0;
        IERC20(rewardToken).transfer(_receiver, r);
    }

    function mint(address gauge) external {
        claim_rewards(msg.sender, msg.sender);
    }

    function claimable_tokens(address _user) external returns (uint256) {
        return pendingRewards[_user][rewardToken];
    }
}
