// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IMuxRebalancerCallback.sol";
import "../interfaces/IOrderBook.sol";

contract TestRebalancer is IMuxRebalancerCallback {
    using SafeERC20 for IERC20;

    address _liquidityPool;
    address _orderBook;

    /**
     * keccak256('TestRebalancer.userData')
     */
    bytes32 internal constant USER_DATA = 0xe0e5df977c8fd4547a156835a1328d03794e4b169d7d6d318bcbe2516bd8265b;

    constructor(address liquidityPool_, address orderBook_) {
        _liquidityPool = liquidityPool_;
        _orderBook = orderBook_;
    }

    function placeOrder(
        uint8 tokenId0,
        uint8 tokenId1,
        uint96 rawAmount0, // erc20.decimals
        uint96 maxRawAmount1 // erc20.decimals
    ) external {
        IOrderBook(_orderBook).placeRebalanceOrder(tokenId0, tokenId1, rawAmount0, maxRawAmount1, USER_DATA);
    }

    function muxRebalanceCallback(
        address token0,
        address token1,
        uint256 rawAmount0,
        uint256 minRawAmount1,
        bytes32 data
    ) external {
        token0;
        rawAmount0;
        require(msg.sender == _liquidityPool, "sender is not pool");
        require(data == USER_DATA, "data mismatch");
        IERC20(token1).transfer(_liquidityPool, minRawAmount1);
    }
}
