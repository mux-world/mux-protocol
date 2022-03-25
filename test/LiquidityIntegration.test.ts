import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, rate, PreMinedTokenTotalSupply, createFactory } from "./deployUtils"
import { createContract, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { MlpToken, OrderBook, TestLiquidityPool, LiquidityManager } from "../typechain"
const U = ethers.utils

describe("Integration", () => {
  const zeroAddress = "0x0000000000000000000000000000000000000000"
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let orderBook: OrderBook
  let liquidityManager: LiquidityManager
  let usdc: Contract
  let usdt: Contract
  let wbtc: Contract
  let muxUsdc: Contract
  let muxWbtc: Contract
  let muxUsdt: Contract

  let trader1: SignerWithAddress
  let lp1: SignerWithAddress
  let broker: SignerWithAddress

  before(async () => {
    const accounts = await ethers.getSigners()
    trader1 = accounts[0]
    lp1 = accounts[1]
    broker = accounts[2]
  })

  beforeEach(async () => {
    const poolHop1 = await createContract("TestLiquidityPoolHop1", [])
    const poolHop2 = await createContract("TestLiquidityPoolHop2", [])
    pool = (await createFactory("TestLiquidityPool")).attach(poolHop1.address)
    mlp = (await createContract("MlpToken")) as MlpToken
    orderBook = (await createContract("OrderBook")) as OrderBook
    liquidityManager = (await createContract("LiquidityManager")) as LiquidityManager
    await orderBook.initialize(pool.address, mlp.address, weth9)
    await orderBook.addBroker(broker.address)
    await liquidityManager.initialize(pool.address)
    await pool.initialize(poolHop2.address, mlp.address, orderBook.address, liquidityManager.address, weth9)
    // fundingInterval, liquidityLockPeriod
    await pool.setNumbers(8 * 3600, 5 * 60)
    await mlp.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    usdc = await createContract("MockERC20", ["Usdc", "Usdc", 6])
    await usdc.mint(lp1.address, toUnit("1000000", 6))
    await usdc.mint(trader1.address, toUnit("100000", 6))

    usdt = await createContract("MockERC20", ["Usdt", "Usdt", 6])
    await usdt.mint(lp1.address, toUnit("1000000", 6))
    await usdt.mint(trader1.address, toUnit("100000", 6))

    wbtc = await createContract("MockERC20", ["Wbtc", "Wbtc", 18])
    await wbtc.mint(lp1.address, toWei("1000"))
    await wbtc.mint(trader1.address, toWei("100"))

    muxUsdc = await createContract("MuxToken", ["muxUsdc", "muxUsdc"])
    await muxUsdc.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    muxWbtc = await createContract("MuxToken", ["muxWbtc", "muxWbtc"])
    await muxWbtc.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    muxUsdt = await createContract("MuxToken", ["muxUsdt", "muxUsdt"])
    await muxUsdt.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    // 0 = USDC
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("USDC"), 6, true, usdc.address, muxUsdc.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setAssetParams(0, rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1, "0x0000000000000000000000000000000000000000", 0)
    // id, tradable, openable, shortable, useStable
    await pool.setAssetFlags(0, false, false, false, false)
    await pool.setFundingParams(0, rate("0.0002"), rate("0.0008"))

    // 1 = BTC
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(1, toBytes32("BTC"), 18, false, wbtc.address, muxWbtc.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setAssetParams(
      1,
      rate("0.1"),
      rate("0.05"),
      rate("0.001"),
      rate("0.01"),
      10,
      toWei("10000000"),
      toWei("10000000"),
      2,
      "0x0000000000000000000000000000000000000000",
      0
    )
    // id, tradable, openable, shortable, useStable
    await pool.setAssetFlags(1, true, true, true, false)
    await pool.setFundingParams(1, rate("0.0003"), rate("0.0009"))

    // 2 = USDT
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(2, toBytes32("USDT"), 6, true, usdt.address, muxUsdt.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setAssetParams(2, rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1, "0x0000000000000000000000000000000000000000", 0)
    // id, tradable, openable, shortable, useStable
    await pool.setAssetFlags(2, false, false, false, false)
    await pool.setFundingParams(2, rate("0.0002"), rate("0.0008"))

    await pool.setBlockTimestamp(86400 * 1)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")])
    await pool.setBlockTimestamp(86400 * 2)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")])
  })

  it("curve", async () => {
    // console.log((await pool.getAllAssetInfo()).map(x => { return { id: x.id, address: x.tokenAddress } }));

    const curve2pool = await createContract("Curve2Pool", [
      [usdc.address, usdt.address],
      1000,
      4000000, //fee 0.04%
      5000000000, // adminFee 0.5
      "USDC-USDT",
      "USDC-USDT",
    ])
    const curve2conn = await createContract("Curve2PoolConnector")
    const lpStake = await createContract("MockLpStake", [curve2pool.address])

    // curve
    await usdc.connect(lp1).approve(curve2pool.address, toWei("10000"))
    await usdt.connect(lp1).approve(curve2pool.address, toWei("10000"))
    await curve2pool.connect(lp1).add_liquidity([toUnit("100", 6), toUnit("100", 6)], 0)
    // console.log("lp1.curveLpBalance", await curve2pool.balanceOf(lp1.address));

    // mux - liquidity
    await usdc.connect(lp1).approve(orderBook.address, toWei("100000"))
    await orderBook.connect(lp1).placeLiquidityOrder(0, toUnit("100000", 6), true)
    await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1"), toWei("1"), rate("0.0001"))

    await usdt.connect(lp1).approve(orderBook.address, toWei("100000"))
    await orderBook.connect(lp1).placeLiquidityOrder(2, toUnit("100000", 6), true)
    await orderBook.connect(broker).fillLiquidityOrder(1, toWei("1"), toWei("1"), rate("0.0001"))
    // mux - connector
    await liquidityManager.addDexSpotConfiguration(
      "curve2pool",
      100,
      [0, 2], // usdc - usdt
      [1, 1]
    )
    await liquidityManager.setDexConnector(
      0,
      curve2conn.address,
      U.defaultAbiCoder.encode(["address", "address", "address", "address", "uint256"], [curve2pool.address, usdc.address, usdt.address, lpStake.address, 0])
    )
    var tx = await liquidityManager.addDexLiquidity(0, [toUnit("100", 6), toUnit("100", 6)], 9647270072)
    console.log("    addDexLiquidity(curve): ", (await tx.wait()).gasUsed)
    expect(await lpStake.balanceOf(liquidityManager.address)).to.equal(toWei("199.92")) // 200 - 200 * 0.004% [fee == 0.04 usdc + 0.04 usdt, 50% goes to admin fee]
    expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("99900", 6))
    expect(await usdt.balanceOf(pool.address)).to.equal(toUnit("99900", 6))

    await liquidityManager.removeDexLiquidity(0, toWei("199.92"), [0, 0], 9647270072)
    expect(await lpStake.balanceOf(liquidityManager.address)).to.equal(toWei("0"))
    expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("99999.969997", 6)) // 99900 + 199980000 * 199.92 / 399.92 = 99900 + 99.969997 = 99999.969997
    expect(await usdt.balanceOf(pool.address)).to.equal(toUnit("99999.969997", 6)) // 99900 + 199980000 * 199.92 / 399.92 = 99900 + 99.969997 = 99999.969997
  })
})
