// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IConnector {
    function name() external view returns (string memory);

    function validate(bytes memory dexData) external;

    function getLpToken(bytes memory dexData) external view returns (address);

    function getLpBalance(bytes memory dexData) external view returns (uint256);

    function getDexRewards(bytes memory dexData)
        external
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    function getDexFees(bytes memory dexData) external returns (uint256[] memory feeAmounts);

    function getDexRedeemableAmounts(bytes memory dexData, uint256 shareAmount)
        external
        returns (uint256[] memory amounts);

    function addDexLiquidity(
        bytes memory dexData,
        uint256[] calldata maxAmounts,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory addedAmounts, uint256 liquidityAmount);

    function removeDexLiquidity(
        bytes memory dexData,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory removedAmounts);
}
