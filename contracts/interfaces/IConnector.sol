// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IConnector {
    function name() external view returns (string memory);

    function validate(bytes memory dexContext) external;

    function getLpBalance(bytes memory dexContext) external returns (uint256);

    function getDexRewards(bytes memory dexContext)
        external
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    function getDexFees(bytes memory dexContext) external returns (uint256[] memory feeAmounts);

    function getDexRedeemableAmounts(bytes memory dexContext, uint256 shareAmount)
        external
        returns (uint256[] memory amounts);

    function claimDexRewards(bytes memory dexContext)
        external
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    function addDexLiquidity(
        bytes memory dexContext,
        uint256[] calldata maxAmounts,
        uint256[] calldata minAmounts,
        uint256 deadline
    )
        external
        returns (
            bytes memory newDexContext,
            uint256[] memory addedAmounts,
            uint256 liquidityAmount,
            uint256[] memory feeAmounts
        );

    function removeDexLiquidity(
        bytes memory dexContext,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    )
        external
        returns (
            bytes memory newDexContext,
            uint256[] memory removedAmounts,
            uint256[] memory feeAmounts
        );
}
