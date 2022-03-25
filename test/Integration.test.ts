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
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let orderBook: OrderBook
  let liquidityManager: LiquidityManager
  let usdc: Contract
  let wbtc: Contract
  let muxUsdc: Contract
  let muxWbtc: Contract

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

    wbtc = await createContract("MockERC20", ["Wbtc", "Wbtc", 18])
    await wbtc.mint(lp1.address, toWei("1000"))
    await wbtc.mint(trader1.address, toWei("100"))

    muxUsdc = await createContract("MuxToken", ["muxUsdc", "muxUsdc"])
    await muxUsdc.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    muxWbtc = await createContract("MuxToken", ["muxWbtc", "muxWbtc"])
    await muxWbtc.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

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

    await pool.setBlockTimestamp(86400 * 1)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")])
    await pool.setBlockTimestamp(86400 * 2)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")])
  })

  it("deposit, withdraw collateral when position = 0", async () => {
    // usdc
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      const tx1 = await orderBook.connect(trader1).depositCollateral(shortAccountId, toUnit("1000", 6))
      const receipt1 = await tx1.wait()
      console.log("GAS short deposit", receipt1.gasUsed.toString(), tx1.hash)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000", 6))
    }
    {
      await pool.connect(trader1).withdrawAllCollateral(shortAccountId)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("0", 6))
    }
    // wbtc
    const longAccountId = assembleSubAccountId(trader1.address, 1, 1, true)
    await wbtc.connect(trader1).approve(orderBook.address, toWei("10"))
    {
      const tx1 = await orderBook.connect(trader1).depositCollateral(longAccountId, toWei("10"))
      const receipt1 = await tx1.wait()
      console.log("GAS long  deposit", receipt1.gasUsed.toString(), tx1.hash)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("90"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("10"))
    }
  })
  it("most commonly used functions", async () => {
    // +liq usdc
    await usdc.connect(lp1).approve(orderBook.address, toUnit("1000000", 6))
    {
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(0, toUnit("1000000", 6), true)
      const receipt1 = await tx1.wait()
      console.log("GAS +liq order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 0, 0, toUnit("1000000", 6), true)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000000", 6))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(true)
    }
    {
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1"), toWei("1000"), rate("0.0001"))
      const receipt1 = await tx1.wait()
      console.log("GAS +liq fill ", receipt1.gasUsed.toString(), tx1.hash)
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000000", 6))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1000000"))
      expect(collateralInfo.collectedFee).to.equal(toWei("100"))
    }
    {
      await expect(pool.connect(lp1).claimMLP()).to.be.revertedWith("Lck")
      await pool.setBlockTimestamp(86400 * 2 + 300)
      await pool.connect(lp1).claimMLP()
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999.9")) // fee = 100, (1000000 - fee) / 1000
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999000.1"))
    }
    // -liq usdc
    await mlp.connect(lp1).approve(orderBook.address, toWei("1"))
    {
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(0, toWei("1"), false)
      const receipt1 = await tx1.wait()
      console.log("GAS -liq order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 1, 0, toWei("1"), false)
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("998.9"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("1"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999000.1"))
    }
    {
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(1, toWei("1"), toWei("2000"), rate("0.0001"))
      const receipt1 = await tx1.wait()
      console.log("GAS -liq fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("1999.8", 6)) // fee = 0.2, 1 * 2000 - fee
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("998000.2", 6))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("998.9"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999001.1"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("998000.2"))
      expect(collateralInfo.collectedFee).to.equal(toWei("100.2"))
    }
    // +liq wbtc
    await wbtc.connect(lp1).approve(orderBook.address, toWei("100"))
    {
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(1, toWei("100"), true)
      const receipt1 = await tx1.wait()
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 2, 1, toWei("100"), true)
      expect(await wbtc.balanceOf(lp1.address)).to.equal(toWei("900"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("100"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("0"))
    }
    {
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(2, toWei("1000"), toWei("1000"), rate("0.0001"))
      const receipt1 = await tx1.wait()
      expect(await wbtc.balanceOf(lp1.address)).to.equal(toWei("900"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("998.9"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999001.1"))
      const collateralInfo = await pool.getAssetInfo(1)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("100")) // fee = 0.01
      expect(collateralInfo.collectedFee).to.equal(toWei("0.01"))
    }
    {
      await pool.setBlockTimestamp(86400 * 2 + 600)
      await pool.connect(lp1).claimMLP()
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("1098.89")) // (100 - fee) * 1000 / 1000
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999998901.11"))
    }
    // open short btc, using usdc
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      const tx1 = await orderBook
        .connect(trader1)
        .placePositionOrder(shortAccountId, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition)
      const receipt1 = await tx1.wait()
      console.log("GAS +sht order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(shortAccountId, 3, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("998000.2"))
      expect(collateralInfo.collectedFee).to.equal(toWei("100.2"))
    }
    {
      const tx1 = await orderBook.connect(broker).fillPositionOrder(3, toWei("1"), toWei("2000"), toWei("0"))
      const receipt1 = await tx1.wait()
      console.log("GAS +sht fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999000.2", 6))
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0006"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("998002.2"))
      expect(collateralInfo.collectedFee).to.equal(toWei("102.2"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
    // open long btc, using wbtc
    const longAccountId = assembleSubAccountId(trader1.address, 1, 1, true)
    await wbtc.connect(trader1).approve(orderBook.address, toWei("10"))
    {
      const tx1 = await orderBook.connect(trader1).placePositionOrder(longAccountId, toWei("10"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition)
      const receipt1 = await tx1.wait()
      console.log("GAS +lng order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 4, toWei("10"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("90"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("10"))
    }
    {
      const tx1 = await orderBook.connect(broker).fillPositionOrder(4, toWei("2000"), toWei("2000"), toWei("0"))
      const receipt1 = await tx1.wait()
      console.log("GAS +lng fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("90"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("110"))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("9.999")) // fee = 0.001
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("100.001"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.011"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    // close short, profit in usdc
    {
      const tx1 = await orderBook
        .connect(trader1)
        .placePositionOrder(shortAccountId, toUnit("0", 6), toWei("1"), toWei("3000"), 0, PositionOrderFlags.WithdrawAllIfEmpty)
      const receipt1 = await tx1.wait()
      console.log("GAS -sht order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(shortAccountId, 5, toUnit("0", 6), toWei("1"), toWei("3000"), 0, PositionOrderFlags.WithdrawAllIfEmpty)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999000.2", 6))
    }
    {
      const tx1 = await orderBook.connect(broker).fillPositionOrder(5, toWei("1"), toWei("1900"), toWei("1")) // pnl = 100
      const receipt1 = await tx1.wait()
      console.log("GAS -sht fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100096.1", 6)) // fee = 1.9, 99000 + 100 - 1.9 + 998
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("997904.1", 6)) // 999000.2 - (100 - 1.9 + 998)
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("997904.1")) // 998002.2 - (100 - 1.9)
      expect(collateralInfo.collectedFee).to.equal(toWei("104.1"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    // close long, profit in wbtc
    {
      const tx1 = await orderBook
        .connect(trader1)
        .placePositionOrder(longAccountId, toWei("0"), toWei("1"), toWei("1000"), 0, PositionOrderFlags.WithdrawAllIfEmpty)
      const receipt1 = await tx1.wait()
      console.log("GAS -lng order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 6, toWei("0"), toWei("1"), toWei("1000"), 0, PositionOrderFlags.WithdrawAllIfEmpty)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("90"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("110"))
    }
    {
      const tx1 = await orderBook.connect(broker).fillPositionOrder(6, toWei("2100"), toWei("2100"), toWei("2100")) // pnl = 100
      const receipt1 = await tx1.wait()
      console.log("GAS -lng fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("100.045619047619047619")) // fee = 0.001, 90 + 9.999 + 100/2100 - fee = 100.04561904761904761904761904762
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("99.954380952380952381")) // 110 - (9.999 + 100/2100 - fee)
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("99.954380952380952381")) // 100.001 + 0.001 - 100/2100
      expect(assetInfo.collectedFee).to.equal(toWei("0.012"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
  })
  it("muxToken", async () => {
    // TODO: remove liquidity in muxEth
    // TODO: close long, profit in muxEth
  })
  it("withdraw", async () => {
    // TODO: withdraw collateral
    // TODO: withdraw profit
  })
})
