// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IDexLiquidityModule {
    function getLpBalance() external view returns (uint256);

    function getFees()
        external
        view
        returns (
            address[] memory token,
            uint256[] memory collectedFeeAmounts,
            uint256[] memory pendingFeeAmounts
        );

    function getSpotAmounts(uint256 shareAmount) external view returns (uint256[] memory amounts);

    function getValidationData(uint256[] memory amounts) external view returns (bytes memory data);

    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 price);

    function addLiquidity(
        uint256[] calldata maxAmounts,
        uint256 deadline,
        bytes memory validationData
    ) external returns (uint256[] memory addedAmounts, uint256 liquidityAmount);

    function removeLiquidity(
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory removedAmounts);
}
