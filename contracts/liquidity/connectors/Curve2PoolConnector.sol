// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../interfaces/IConnector.sol";

interface ICurve2Pool {
    function balances(uint256 index) external view returns (uint256);

    function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external returns (uint256);

    function remove_liquidity(uint256 _burn_amount, uint256[2] memory _min_amounts)
        external
        returns (uint256[2] memory);

    function get_virtual_price() external view returns (uint256);
}

interface IStake {
    function stake(uint256 amount) external;

    function redeem(uint256 amount) external;
}

contract Curve2PoolConnector is IConnector {
    using Address for address;

    struct DexContext {
        address pool;
        address tokenA;
        address tokenB;
        address stake;
        uint256 vPrice;
    }

    function name() public view override returns (string memory) {
        return "CurveConnector";
    }

    function validate(bytes memory context) public view override {
        DexContext memory dexContext = _getDexContext(context);
        require(dexContext.pool.isContract(), "P!C");
        require(dexContext.tokenA.isContract(), "A!C");
        require(dexContext.tokenB.isContract(), "B!C");
        require(dexContext.stake == address(0) || dexContext.stake.isContract(), "S!C");
    }

    function getLpBalance(bytes memory context) public override returns (uint256) {
        DexContext memory dexContext = _getDexContext(context);
        uint256[] memory feeAmounts = _getFeeAmounts(dexContext);
        uint256 feeShareAmount = _getFeeShareAmount(dexContext, feeAmounts);
        return IERC20(dexContext.pool).balanceOf(address(this)) - feeShareAmount;
    }

    function getDexRewards(bytes memory context)
        public
        override
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {}

    function getDexFees(bytes memory context) public returns (uint256[] memory feeAmounts) {
        DexContext memory dexContext = _getDexContext(context);
        feeAmounts = _getFeeAmounts(dexContext);
    }

    function getDexRedeemableAmounts(bytes memory context, uint256 shareAmount)
        public
        override
        returns (uint256[] memory amounts)
    {
        DexContext memory dexContext = _getDexContext(context);
        uint256 totalSupply = IERC20(dexContext.pool).totalSupply();
        (uint256 reservedA, uint256 reservedB) = _getReserves(dexContext);
        amounts = new uint256[](2);
        amounts[0] = (reservedA * shareAmount) / totalSupply;
        amounts[1] = (reservedB * shareAmount) / totalSupply;
    }

    function claimDexRewards(bytes memory dexContext)
        external
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {}

    function addDexLiquidity(
        bytes memory context,
        uint256[] calldata maxAmounts,
        uint256[] calldata minAmounts,
        uint256
    )
        public
        override
        returns (
            bytes memory newDexContext,
            uint256[] memory addedAmounts,
            uint256 liquidityAmount,
            uint256[] memory feeAmounts
        )
    {
        require(maxAmounts.length == 2, "L!2");
        require(maxAmounts.length == minAmounts.length, "L!L");
        DexContext memory dexContext = _getDexContext(context);
        feeAmounts = _getFeeAmounts(dexContext);
        uint256 feeShareAmount = _getFeeShareAmount(dexContext, feeAmounts);
        if (feeShareAmount > 0) {
            IERC20(dexContext.pool).approve(dexContext.pool, feeShareAmount);
            ICurve2Pool(dexContext.pool).remove_liquidity(feeShareAmount, _toArray2(feeAmounts));
        }
        dexContext.vPrice = ICurve2Pool(dexContext.pool).get_virtual_price();
        IERC20(dexContext.tokenA).approve(dexContext.pool, maxAmounts[0]);
        IERC20(dexContext.tokenB).approve(dexContext.pool, maxAmounts[1]);
        liquidityAmount = ICurve2Pool(dexContext.pool).add_liquidity(_toArray2(maxAmounts), 0);
        addedAmounts = maxAmounts;
        newDexContext = context;
        // TODO: stake to somewhere
        if (dexContext.stake != address(0)) {
            IERC20(dexContext.pool).approve(dexContext.stake, liquidityAmount);
            IStake(dexContext.stake).stake(liquidityAmount);
        }
    }

    function removeDexLiquidity(
        bytes memory context,
        uint256 shareAmount,
        uint256[] calldata minAmounts,
        uint256
    )
        public
        override
        returns (
            bytes memory newDexContext,
            uint256[] memory removedAmounts,
            uint256[] memory feeAmounts
        )
    {
        require(minAmounts.length == 2, "L!2");
        DexContext memory dexContext = _getDexContext(context);
        if (dexContext.stake != address(0)) {
            IStake(dexContext.stake).redeem(shareAmount);
        }
        feeAmounts = _getFeeAmounts(dexContext);
        uint256 feeShareAmount = _getFeeShareAmount(dexContext, feeAmounts);
        uint256[2] memory amounts;
        amounts[0] = minAmounts[0] + feeAmounts[0];
        amounts[1] = minAmounts[1] + feeAmounts[1];
        removedAmounts = new uint256[](2);
        removedAmounts = _toSlice(ICurve2Pool(dexContext.pool).remove_liquidity(shareAmount + feeShareAmount, amounts));
        newDexContext = context;
    }

    function _getFeeAmounts(DexContext memory dexContext) internal view returns (uint256[] memory feeAmounts) {
        uint256 vPrice = ICurve2Pool(dexContext.pool).get_virtual_price();
        uint256 rate = dexContext.vPrice > vPrice ? dexContext.vPrice - vPrice : 0;
        feeAmounts = new uint256[](2);
        if (rate != 0) {
            uint256 shareAmount = IERC20(dexContext.pool).balanceOf(address(this));
            uint256 totalSupply = IERC20(dexContext.pool).totalSupply();
            (uint256 reservedA, uint256 reservedB) = _getReserves(dexContext);
            feeAmounts[0] = (((reservedA * shareAmount) / totalSupply) * rate) / vPrice;
            feeAmounts[1] = (((reservedB * shareAmount) / totalSupply) * rate) / vPrice;
        }
    }

    function _getFeeShareAmount(DexContext memory dexContext, uint256[] memory feeAmounts)
        internal
        view
        returns (uint256 shareAmount)
    {
        require(feeAmounts.length == 2, "F!2");
        uint256 totalSupply = IERC20(dexContext.pool).totalSupply();
        (uint256 reservedA, uint256 reservedB) = _getReserves(dexContext);
        uint256 shareAmountA = (feeAmounts[0] * totalSupply) / reservedA;
        uint256 shareAmountB = (feeAmounts[1] * totalSupply) / reservedB;
        shareAmount = shareAmountA >= shareAmountB ? shareAmountA : shareAmountB;
    }

    function _toArray2(uint256[] memory amounts_) internal pure returns (uint256[2] memory amounts) {
        require(amounts_.length == 2, "L!2");
        amounts[0] = amounts_[0];
        amounts[1] = amounts_[1];
    }

    function _toSlice(uint256[2] memory amounts_) internal pure returns (uint256[] memory amounts) {
        require(amounts_.length == 2, "L!2");
        amounts = new uint256[](2);
        amounts[0] = amounts_[0];
        amounts[1] = amounts_[1];
    }

    function _getReserves(DexContext memory dexContext) internal view returns (uint256, uint256) {
        return (ICurve2Pool(dexContext.pool).balances(0), ICurve2Pool(dexContext.pool).balances(1));
    }

    function _getDexContext(bytes memory context) internal pure returns (DexContext memory) {
        return abi.decode(context, (DexContext));
    }

    function _writeContext(DexContext memory dexContext) internal pure returns (bytes memory) {
        return abi.encode(dexContext);
    }
}
