// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./MockERC20.sol";
import "hardhat/console.sol";

contract MockUniV2Pool {
    using Address for address;
    struct Pool {
        address lpToken;
        uint256 reserveA;
        uint256 reserveB;
        uint256 variance;
    }

    mapping(bytes32 => Pool) public pools;

    function deposit(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external {
        Pool storage pool = pools[_key(tokenA, tokenB)];

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        pool.reserveA += amountA;
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        pool.reserveB += amountB;
    }

    function initLpToken(address tokenA, address tokenB) external {
        Pool storage pool = pools[_key(tokenA, tokenB)];
        pool.lpToken = address(new MockERC20("LPT", "LPT", 18));
    }

    function lpToken(address tokenA, address tokenB) public view returns (address) {
        return pools[_key(tokenA, tokenB)].lpToken;
    }

    function withdraw(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external {
        Pool storage pool = pools[_key(tokenA, tokenB)];

        IERC20(tokenA).transfer(msg.sender, amountA);
        pool.reserveA -= amountA;
        IERC20(tokenB).transfer(msg.sender, amountB);
        pool.reserveB -= amountB;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        require(block.timestamp <= deadline, "Deadline");
        Pool storage pool = pools[_key(tokenA, tokenB)];

        if (pool.reserveA == 0 && pool.reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBRequired = (amountADesired * pool.reserveB) / pool.reserveA;
            if (amountBRequired <= amountBDesired) {
                require(amountBRequired >= amountBMin, "amountBRequired < amountBMin");
                (amountA, amountB) = (amountADesired, amountBRequired);
            } else {
                uint256 amountARequired = (amountBDesired * pool.reserveA) / pool.reserveB;
                require(amountARequired <= amountADesired, "amountARequired > amountADesired");
                require(amountARequired >= amountAMin, "amountARequired < amountAMin");
                (amountA, amountB) = (amountARequired, amountBDesired);
            }
        }

        uint256 totalSupply = IERC20(pool.lpToken).totalSupply();
        if (totalSupply != 0) {
            uint256 p1 = (amountA * totalSupply) / pool.reserveA;
            uint256 p2 = (amountB * totalSupply) / pool.reserveB;
            liquidity = p1 <= p2 ? p1 : p2;
        } else {
            liquidity = (amountA + amountB) / 2;
        }

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        pool.reserveA += amountA;
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        pool.reserveB += amountB;

        if (pool.lpToken == address(0)) {
            pool.lpToken = address(new MockERC20("LPT", "LPT", 18));
        }
        pool.lpToken.functionCall(abi.encodeWithSignature("mint(address,uint256)", to, liquidity));
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(block.timestamp <= deadline, "Deadline");
        Pool storage pool = pools[_key(tokenA, tokenB)];

        uint256 ratio = (liquidity * 1e18) / IERC20(pool.lpToken).totalSupply();
        amountA = (ratio * pool.reserveA) / 1e18;
        require(amountA >= amountAMin, "amountA < amountAMin");
        amountB = (ratio * pool.reserveB) / 1e18;
        require(amountB >= amountBMin, "amountB < amountBMin");

        IERC20(tokenA).transfer(to, amountA);
        pool.reserveA -= amountA;
        IERC20(tokenB).transfer(to, amountB);
        pool.reserveB -= amountB;

        (bool success, ) = pool.lpToken.call(abi.encodeWithSignature("burn(address,uint256)", msg.sender, liquidity));
        require(success, "Burn");
    }

    function _key(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }
}
