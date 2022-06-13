// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "./Storage.sol";
import "./LiquidityPoolHop1.sol";
import "./LiquidityPoolHop2.sol";

/**
 * @dev LiquidityPool uses ChainedProxy pattern, where the external requests call TransparentProxy first, and jump to
 *      hop1, if the function is not implemented in hop1, it fallbacks to hop2.
 *
 *      requests -> TransparentProxy -> LiquidityPoolHop1 -> LiquidityPoolHop2
 *
 *      The real logic are all in LiquidityPoolHop1 and LiquidityPoolHop2. LiquidityPool is only used for generating
 *      typechain and tests.
 */
contract LiquidityPool is Storage, LiquidityPoolHop1, LiquidityPoolHop2 {

}
