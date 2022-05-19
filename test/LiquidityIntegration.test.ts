import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, rate, PreMinedTokenTotalSupply, createFactory } from "./deployUtils"
import { createContract } from "./deployUtils"
import { MlpToken, OrderBook, TestLiquidityPool, LiquidityManager } from "../typechain"
const U = ethers.utils

describe("LiquidityIntegration", () => {
  const zeroAddress = "0x0000000000000000000000000000000000000000"
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let orderBook: OrderBook
  let liquidityManager: LiquidityManager
  let usdc: Contract
  let usdt: Contract
  let wbtc: Contract
  let muxUsd: Contract
  let muxWbtc: Contract

  let trader1: SignerWithAddress
  let lp1: SignerWithAddress
  let broker: SignerWithAddress
  let vault: SignerWithAddress

  before(async () => {
    const accounts = await ethers.getSigners()
    trader1 = accounts[0]
    lp1 = accounts[1]
    broker = accounts[2]
    vault = accounts[3]
  })

  beforeEach(async () => {
    const poolHop1 = await createContract("TestLiquidityPoolHop1")
    const poolHop2 = await createContract("TestLiquidityPoolHop2")
    pool = (await createFactory("TestLiquidityPool")).attach(poolHop1.address)
    mlp = (await createContract("MlpToken")) as MlpToken
    orderBook = (await createContract("OrderBook")) as OrderBook
    liquidityManager = (await createContract("LiquidityManager")) as LiquidityManager
    await mlp.initialize("MLP", "MLP")
    await orderBook.initialize(pool.address, mlp.address, weth9, weth9)
    await orderBook.addBroker(broker.address)
    await liquidityManager.initialize(vault.address, pool.address)
    await pool.initialize(poolHop2.address, mlp.address, orderBook.address, liquidityManager.address, weth9, weth9)
    // fundingInterval, mlpPrice, mlpPrice, liqBase, liqDyn
    await pool.setNumbers(3600 * 8, toWei("1"), toWei("2"), rate("0.0001"), rate("0.0000"))
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

    muxUsd = await createContract("MuxToken")
    await muxUsd.initialize("muxUsd", "muxUsd")
    await muxUsd.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    muxWbtc = await createContract("MuxToken")
    await muxWbtc.initialize("muxWbtc", "muxWbtc")
    await muxWbtc.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    // 0 = USDC
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("USDC"), 6, true, usdc.address, muxUsd.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(0, rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1)
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(0, false, false, false, false, true, true)
    await pool.setFundingParams(0, rate("0.0002"), rate("0.0008"))

    // 1 = BTC
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(1, toBytes32("BTC"), 18, false, wbtc.address, muxWbtc.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(1, rate("0.1"), rate("0.05"), rate("0.001"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2)
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(1, true, true, true, false, true, false)
    await pool.setFundingParams(1, rate("0.0003"), rate("0.0009"))

    // 2 = USDT
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(2, toBytes32("USDT"), 6, true, usdt.address, muxUsd.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(2, rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1)
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(2, false, false, false, false, true, true)
    await pool.setFundingParams(2, rate("0.0002"), rate("0.0008"))

    await pool.setBlockTimestamp(86400 * 1)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
    await pool.setBlockTimestamp(86400 * 2)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
  })

  function makeCallContext(methodId: string, paramTypes: any, params: any, dexId: number = 0) {
    return {
      methodId: toBytes32(methodId),
      params: U.defaultAbiCoder.encode(paramTypes, params),
      dexId: dexId,
    }
  }

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

    const lpStake = await createContract("MockLpStake", [curve2pool.address])
    const transferMod = await createContract("TransferModule")
    const curveMod = await createContract("CurveFarmModule", [curve2pool.address, usdc.address, usdt.address, lpStake.address])

    // curve
    await usdc.connect(lp1).approve(curve2pool.address, toWei("10000"))
    await usdt.connect(lp1).approve(curve2pool.address, toWei("10000"))
    await curve2pool.connect(lp1).add_liquidity([toUnit("100", 6), toUnit("100", 6)], 0)
    // console.log("lp1.curveLpBalance", await curve2pool.balanceOf(lp1.address));

    // mux - liquidity
    const current = toWei("29700")
    const target = toWei("29700")
    await usdc.connect(lp1).approve(orderBook.address, toWei("100000"))
    await orderBook.connect(lp1).placeLiquidityOrder(0, toUnit("100000", 6), true)
    await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1"), toWei("1"), current, target)

    await usdt.connect(lp1).approve(orderBook.address, toWei("100000"))
    await orderBook.connect(lp1).placeLiquidityOrder(2, toUnit("100000", 6), true)
    await orderBook.connect(broker).fillLiquidityOrder(1, toWei("1"), toWei("1"), current, target)

    const dl = await createContract("DexLiquidity", [liquidityManager.address])
    await liquidityManager.addExternalAccessor(dl.address)
    // mux - connector
    await liquidityManager.addDexSpotConfiguration(
      "curve2pool",
      100,
      [0, 2], // usdc - usdt
      [1, 1]
    )
    await liquidityManager.installGenericModule(transferMod.address)
    await liquidityManager.installDexModule(1, curveMod.address)

    var tx = await liquidityManager.batchModuleCall([
      makeCallContext(
        "transferFromPool",
        ["uint8[]", "uint256[]"],
        [
          [0, 2],
          [toUnit("100", 6), toUnit("100", 6)],
        ]
      ),
      makeCallContext("addLiquidity", ["uint256[]", "uint256[]", "uint256"], [[toUnit("100", 6), toUnit("100", 6)], [0, 0], 99999999999], 1),
    ])
    console.log("    addDexLiquidity(curve): ", (await tx.wait()).gasUsed)
    expect(await lpStake.balanceOf(liquidityManager.address)).to.equal(toWei("199.92")) // 200 - 200 * 0.004% [fee == 0.04 usdc + 0.04 usdt, 50% goes to admin fee]
    var result = await dl.callStatic.getDexLiquidity(1)
    expect(result.lpBalance).to.equal(toWei("199.92"))

    expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("99900", 6))
    expect(await usdt.balanceOf(pool.address)).to.equal(toUnit("99900", 6))

    var tx = await liquidityManager.batchModuleCall([
      makeCallContext("removeLiquidity", ["uint256", "uint256[]", "uint256"], [toWei("199.92"), [0, 0], 99999999999], 1),
    ])
    console.log("    removeDexLiquidity(curve): ", (await tx.wait()).gasUsed)
    expect(await lpStake.balanceOf(liquidityManager.address)).to.equal(toWei("0"))
    expect(await usdc.balanceOf(liquidityManager.address)).to.equal(toUnit("99.969997", 6)) // 99900 + 199980000 * 199.92 / 399.92 = 99900 + 99.969997 = 99999.969997
    expect(await usdt.balanceOf(liquidityManager.address)).to.equal(toUnit("99.969997", 6)) // 99900 + 199980000 * 199.92 / 399.92 = 99900 + 99.969997 = 99999.969997
    await liquidityManager.batchModuleCall([
      makeCallContext(
        "transferToPool",
        ["uint8[]", "uint256[]"],
        [
          [0, 2],
          [toUnit("99.969997", 6), toUnit("99.969997", 6)],
        ]
      ),
    ])
    expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("99999.969997", 6)) // 99900 + 199980000 * 199.92 / 399.92 = 99900 + 99.969997 = 99999.969997
    expect(await usdt.balanceOf(pool.address)).to.equal(toUnit("99999.969997", 6)) // 99900 + 199980000 * 199.92 / 399.92 = 99900 + 99.969997 = 99999.969997
  })
})
