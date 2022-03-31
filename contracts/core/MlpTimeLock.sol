// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../components/SafeOwnable.sol";
import "../libraries/LibMath.sol";
import "../interfaces/IMlpTimeLock.sol";

/**
 * @notice When a Liquidity Provider adds liquidity, the MLP token will be locked into MlpTimeLock.
 *         The Liquidity Provider can claim() the MLP token after a period of time.
 */
contract MlpTimeLock is Initializable, SafeOwnable, IMlpTimeLock {
    address _mlp;
    address _pool;
    uint32 _liquidityLockPeriod; // 1e0
    mapping(address => LiquidityLock) _liquidityLocks;

    event ClaimMlp(address indexed lp, uint96 mlpAmount);
    event AddMlp(address indexed lp, uint96 mlpAmount);
    event SetLiquidityLockPeriod(uint32 oldLockPeriod, uint32 newLockPeriod);

    struct LiquidityLock {
        uint32 lastAddedTime; // 1e0
        uint96 pendingMLP;
    }

    function initialize(address mlp, address pool) external initializer {
        __SafeOwnable_init();

        _mlp = mlp;
        _pool = pool;
    }

    function getLiquidityLockInfo(address lp)
        external
        view
        returns (
            uint32 liquidityLockPeriod,
            uint32 lastAddedTime,
            uint96 pendingMLP
        )
    {
        liquidityLockPeriod = _liquidityLockPeriod;
        LiquidityLock storage lock = _liquidityLocks[lp];
        lastAddedTime = lock.lastAddedTime;
        pendingMLP = lock.pendingMLP;
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    function claimMlp() external {
        address lp = msg.sender;
        LiquidityLock storage lock = _liquidityLocks[lp];
        require(_blockTimestamp() >= lock.lastAddedTime + _liquidityLockPeriod, "Lck"); // mlp is LoCKed
        uint96 mlpAmount = lock.pendingMLP;
        require(mlpAmount > 0, "A=0"); // Amount Is Zero
        lock.pendingMLP = 0;
        lock.lastAddedTime = 0;
        IERC20Upgradeable(_mlp).transfer(lp, mlpAmount);
        emit ClaimMlp(lp, mlpAmount);
    }

    function addMlp(
        address lp,
        uint96 mlpAmount // LiquidityPool SHOULD sent MlpToken to MlpTimeLock
    ) external {
        require(msg.sender == _pool, "Snd"); // SeNDer is not authorized
        LiquidityLock storage lock = _liquidityLocks[lp];
        lock.pendingMLP += mlpAmount;
        lock.lastAddedTime = _blockTimestamp();
        emit AddMlp(lp, mlpAmount);
    }

    function setLiquidityLockPeriod(uint32 newLiquidityLockPeriod) external onlyOwner {
        require(newLiquidityLockPeriod <= 86400 * 30, "Lck"); // LoCK time is too large
        require(_liquidityLockPeriod != newLiquidityLockPeriod, "Chg"); // setting is not CHanGed
        emit SetLiquidityLockPeriod(_liquidityLockPeriod, newLiquidityLockPeriod);
        _liquidityLockPeriod = newLiquidityLockPeriod;
    }
}
