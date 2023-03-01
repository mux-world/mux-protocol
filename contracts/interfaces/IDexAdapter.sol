// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IDexAdapter {
    function initializeAdapter(bytes memory initialData) external;

    function getLpBalance() external view returns (uint256);

    function getFees()
        external
        returns (
            address[] memory rewardTokens,
            uint256[] memory collectedFeeAmounts,
            uint256[] memory pendingFeeAmounts
        );

    function getTotalSpotAmounts() external view returns (uint256[] memory amounts);

    function getSpotAmounts(uint256 shareAmount) external view returns (uint256[] memory amounts);

    function addLiquidityUniSwapV2(
        uint256[] calldata maxAmounts,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory addedAmounts, uint256 liquidityAmount);

    function addLiquidityCurve(
        uint256[] calldata maxAmounts,
        uint256 minLpAmount
    ) external returns (uint256[] memory addedAmounts, uint256 liquidityAmount);

    function removeLiquidity(
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory removedAmounts);

    function claimFees() external;
}
