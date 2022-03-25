// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IConnector.sol";

contract TestConnector is IConnector {
    function name() public view override returns (string memory) {
        return "TestConnector";
    }

    function validate(bytes memory dexContext) public view override {}

    function getLpBalance(bytes memory) public override returns (uint256) {
        revert("getLpBalanceCalled");
    }

    function getDexRewards(bytes memory) public override returns (address[] memory, uint256[] memory) {
        revert("getDexRewardsCalled");
    }

    function getDexFees(bytes memory) public returns (uint256[] memory) {
        revert("getDexFeesCalled");
    }

    function getDexRedeemableAmounts(bytes memory, uint256) public override returns (uint256[] memory) {
        revert("getDexRedeemableAmountsCalled");
    }

    function claimDexRewards(bytes memory dexContext)
        external
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        revert("claimDexRewardsCalled");
    }

    function addDexLiquidity(
        bytes memory,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    )
        public
        override
        returns (
            bytes memory,
            uint256[] memory,
            uint256,
            uint256[] memory
        )
    {
        revert("addDexLiquidityCalled");
    }

    function removeDexLiquidity(
        bytes memory,
        uint256,
        uint256[] calldata,
        uint256
    )
        public
        override
        returns (
            bytes memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        revert("removeDexLiquidityCalled");
    }
}
