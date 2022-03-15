// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../interfaces/IConnector.sol";

import "hardhat/console.sol";

interface IUniswapV2Router {
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
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

contract UniV2Connector is IConnector {
    using Address for address;

    struct UniV2Context {
        address router;
        address pair;
        address tokenA;
        address tokenB;
    }

    function name() external view override returns (string memory) {
        return "UniV2Connector";
    }

    function getLpToken(bytes memory dexData) external view returns (address) {
        return _getContext(dexData).pair;
    }

    function validate(bytes memory dexData) external view override {
        UniV2Context memory context = _getContext(dexData);
        require(context.router.isContract(), "InvalidRouter");
        require(context.pair.isContract(), "InvalidPair");
        require(context.tokenA.isContract(), "InvalidTokenA");
        require(context.tokenB.isContract(), "InvalidTokenB");
    }

    function getLpBalance(bytes memory dexData) external view override returns (uint256) {
        UniV2Context memory context = _getContext(dexData);
        return IERC20(context.pair).balanceOf(address(this));
    }

    function getDexRewards(bytes memory dexData)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {}

    function getDexFees(bytes memory dexData) external returns (uint256[] memory feeAmounts) {}

    function getDexRedeemableAmounts(bytes memory dexData, uint256 shareAmount)
        external
        override
        returns (uint256[] memory amounts)
    {
        UniV2Context memory context = _getContext(dexData);
        address _token0 = context.tokenA;
        address _token1 = context.tokenB;
        uint256 balance0 = IERC20(_token0).balanceOf(context.pair);
        uint256 balance1 = IERC20(_token1).balanceOf(context.pair);
        uint256 _totalSupply = IERC20(context.pair).totalSupply();
        amounts = new uint256[](2);
        amounts[0] = (shareAmount * balance0) / _totalSupply;
        amounts[1] = (shareAmount * balance1) / _totalSupply;
    }

    function addDexLiquidity(
        bytes memory dexData,
        uint256[] calldata maxAmounts,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external override returns (uint256[] memory addedAmounts, uint256 liquidityAmount) {
        require(maxAmounts.length == 2, "WrongAssetCount");
        require(maxAmounts.length == minAmounts.length, "ParamsLengthMismatch");
        UniV2Context memory context = _getContext(dexData);

        IERC20(context.tokenA).approve(context.router, maxAmounts[0]);
        IERC20(context.tokenB).approve(context.router, maxAmounts[1]);

        addedAmounts = new uint256[](2);
        (addedAmounts[0], addedAmounts[1], liquidityAmount) = IUniswapV2Router(context.router).addLiquidity(
            context.tokenA,
            context.tokenB,
            maxAmounts[0],
            maxAmounts[1],
            minAmounts[0],
            minAmounts[1],
            address(this),
            deadline
        );
    }

    function removeDexLiquidity(
        bytes memory dexData,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external override returns (uint256[] memory removedAmounts) {
        require(minAmounts.length == 2, "WrongAssetCount");
        UniV2Context memory context = _getContext(dexData);

        IERC20(context.pair).approve(context.router, shareAmount);
        removedAmounts = new uint256[](2);
        (removedAmounts[0], removedAmounts[1]) = IUniswapV2Router(context.router).removeLiquidity(
            context.tokenA,
            context.tokenB,
            shareAmount,
            minAmounts[0],
            minAmounts[1],
            address(this),
            deadline
        );
    }

    function _getContext(bytes memory dexData) internal pure returns (UniV2Context memory context) {
        context = abi.decode(dexData, (UniV2Context));
    }
}
