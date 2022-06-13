// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/presets/ERC20PresetMinterPauserUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../components/SafeOwnableUpgradeable.sol";

contract DemoLpMining is Initializable, SafeOwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct UserInfo {
        uint256 amount; // LP tokens provided
        uint256 rewardDebt; // pending reward = user.amount * pool.accRewardPerShare - user.rewardDebt
    }

    struct PoolInfo {
        IERC20Upgradeable lpToken;
        uint256 allocPoint; // weight
        uint256 lastRewardTime;
        uint256 accRewardPerShare; // 1e12
    }

    ERC20PresetMinterPauserUpgradeable public rewardToken;
    uint256 public rewardPerSecond;
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;
    uint256 public startTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function initialize(uint256 rewardPerSecond_, uint256 startTime_) external initializer {
        __SafeOwnable_init();
        rewardToken = new ERC20PresetMinterPauserUpgradeable();
        rewardToken.initialize("DemoMiningReward", "DMR");
        rewardPerSecond = rewardPerSecond_;
        startTime = startTime_;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setRewardPerSecond(uint256 rewardPerSecond_) external onlyOwner {
        updatePools();
        rewardPerSecond = rewardPerSecond_;
    }

    function checkForDuplicate(IERC20Upgradeable lpToken_) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            require(poolInfo[pid].lpToken != lpToken_, "add: pool already exists");
        }
    }

    function add(uint256 allocPoint, IERC20Upgradeable lpToken) external onlyOwner {
        checkForDuplicate(lpToken); // ensure you cant add duplicate pools
        updatePools();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint += allocPoint;
        poolInfo.push(
            PoolInfo({ lpToken: lpToken, allocPoint: allocPoint, lastRewardTime: lastRewardTime, accRewardPerShare: 0 })
        );
    }

    function set(uint256 pid, uint256 allocPoint) external onlyOwner {
        updatePools();
        totalAllocPoint = totalAllocPoint - poolInfo[pid].allocPoint + allocPoint;
        poolInfo[pid].allocPoint = allocPoint;
    }

    function getMultiplier(uint256 from_, uint256 to_) public view returns (uint256) {
        from_ = from_ > startTime ? from_ : startTime;
        if (to_ < startTime) {
            return 0;
        }
        return to_ - from_;
    }

    function pendingReward(uint256 pid, address userAddress) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][userAddress];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 reward = (multiplier * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare += (reward * 1e12) / lpSupply;
        }
        return (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;
    }

    function updatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 pid) public {
        PoolInfo storage pool = poolInfo[pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 reward = (multiplier * rewardPerSecond * pool.allocPoint) / totalAllocPoint;

        rewardToken.mint(address(this), reward);

        pool.accRewardPerShare += (reward * 1e12) / lpSupply;
        pool.lastRewardTime = block.timestamp;
    }

    function deposit(uint256 pid, uint256 amount) public {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        updatePool(pid);
        uint256 pending = (user.amount * pool.accRewardPerShare) / 1e12 - user.rewardDebt;
        user.amount += amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        if (pending > 0) {
            rewardToken.transfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), amount);
        emit Deposit(msg.sender, pid, amount);
    }

    function withdraw(uint256 pid, uint256 amount) public {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amount, "withdraw: not good");
        updatePool(pid);
        uint256 pending = (user.amount * pool.accRewardPerShare) / 1e12 - user.rewardDebt;
        user.amount -= amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        if (pending > 0) {
            rewardToken.transfer(msg.sender, pending);
        }
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit Withdraw(msg.sender, pid, amount);
    }
}
