// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./MockERC20.sol";

contract MockUniV2Pool is ERC20 {
    using Address for address;

    address internal _tokenA;
    address internal _tokenB;
    uint256 internal reserveA;
    uint256 internal reserveB;

    constructor(address tokenA_, address tokenB_) ERC20("MockUniPool", "MUP") {
        _tokenA = tokenA_;
        _tokenB = tokenB_;
    }

    function token0() external view returns (address) {
        return _tokenA;
    }

    function token1() external view returns (address) {
        return _tokenB;
    }

    function getPrice() public view returns (uint256) {
        return (reserveA * 1e18) / reserveB;
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = uint112(reserveA);
        _reserve1 = uint112(reserveB);
        _blockTimestampLast = uint32(block.timestamp);
    }

    function deposit(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external {
        require(tokenA == _tokenA, "!TA");
        require(tokenB == _tokenB, "!TB");
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        reserveA += amountA;
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        reserveB += amountB;
    }

    function withdraw(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external {
        require(tokenA == _tokenA, "!TA");
        require(tokenB == _tokenB, "!TB");
        IERC20(tokenA).transfer(msg.sender, amountA);
        reserveA -= amountA;
        IERC20(tokenB).transfer(msg.sender, amountB);
        reserveB -= amountB;
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
        public
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        require(tokenA == _tokenA, "!TA");
        require(tokenB == _tokenB, "!TB");
        require(block.timestamp <= deadline, "Deadline");
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBRequired = (amountADesired * reserveB) / reserveA;
            if (amountBRequired <= amountBDesired) {
                require(amountBRequired >= amountBMin, "amountBRequired < amountBMin");
                (amountA, amountB) = (amountADesired, amountBRequired);
            } else {
                uint256 amountARequired = (amountBDesired * reserveA) / reserveB;
                require(amountARequired <= amountADesired, "amountARequired > amountADesired");
                require(amountARequired >= amountAMin, "amountARequired < amountAMin");
                (amountA, amountB) = (amountARequired, amountBDesired);
            }
        }

        uint256 totalSupply = totalSupply();
        if (reserveA != 0 && reserveB != 0) {
            uint256 p1 = (amountA * totalSupply) / reserveA;
            uint256 p2 = (amountB * totalSupply) / reserveB;
            liquidity = p1 <= p2 ? p1 : p2;
        } else {
            liquidity = (amountA + amountB) / 2;
        }

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        reserveA += amountA;
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        reserveB += amountB;
        _mint(to, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public returns (uint256 amountA, uint256 amountB) {
        require(tokenA == _tokenA, "!TA");
        require(tokenB == _tokenB, "!TB");
        require(block.timestamp <= deadline, "Deadline");

        uint256 ratio = (liquidity * 1e18) / totalSupply();
        amountA = (ratio * reserveA) / 1e18;
        require(amountA >= amountAMin, "amountA < amountAMin");
        amountB = (ratio * reserveB) / 1e18;
        require(amountB >= amountBMin, "amountB < amountBMin");

        IERC20(tokenA).transfer(to, amountA);
        reserveA -= amountA;
        IERC20(tokenB).transfer(to, amountB);
        reserveB -= amountB;
        _burn(msg.sender, liquidity);
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        return _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountOutNoFee(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function swapA4B(uint256 amountA) external {
        uint256 amountB = _getAmountOut(amountA, reserveA, reserveB);
        IERC20(_tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(_tokenB).transfer(msg.sender, amountB);
        reserveA += amountA;
        reserveB -= amountB;
    }

    function swapB4A(uint256 amountB) external {
        uint256 amountA = _getAmountOut(amountB, reserveB, reserveA);
        IERC20(_tokenB).transferFrom(msg.sender, address(this), amountB);
        IERC20(_tokenA).transfer(msg.sender, amountA);
        reserveA -= amountA;
        reserveB += amountB;
    }
}
