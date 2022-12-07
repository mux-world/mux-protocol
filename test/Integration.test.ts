import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, rate, PreMinedTokenTotalSupply, createFactory } from "./deployUtils"
import { createContract, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { MlpToken, TestOrderBook, TestLiquidityPool, LiquidityManager, Reader } from "../typechain"
const U = ethers.utils

describe("Integration", () => {
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  const refCode = toBytes32("")
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let orderBook: TestOrderBook
  let liquidityManager: LiquidityManager
  let usdc: Contract
  let wbtc: Contract
  let usdt: Contract
  let muxUsd: Contract
  let muxWbtc: Contract
  let reader: Reader

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
    const libLiquidity = await createContract("LibLiquidity")
    const poolHop1 = await createContract("TestLiquidityPoolHop1")
    const poolHop2 = await createContract("TestLiquidityPoolHop2", [], { "contracts/libraries/LibLiquidity.sol:LibLiquidity": libLiquidity })
    pool = await ethers.getContractAt("TestLiquidityPool", poolHop1.address)
    mlp = (await createContract("MlpToken")) as MlpToken
    orderBook = (await createContract("TestOrderBook")) as TestOrderBook
    liquidityManager = (await createContract("LiquidityManager")) as LiquidityManager
    reader = (await createContract("Reader", [pool.address, mlp.address, liquidityManager.address, orderBook.address, []])) as Reader
    await mlp.initialize("MLP", "MLP")
    await orderBook.initialize(pool.address, mlp.address, weth9, weth9)
    await orderBook.addBroker(broker.address)
    await orderBook.setLiquidityLockPeriod(5 * 60)
    await orderBook.setOrderTimeout(300, 86400 * 365)
    await liquidityManager.initialize(vault.address, pool.address)
    await pool.initialize(poolHop2.address, mlp.address, orderBook.address, weth9, weth9, vault.address)
    // fundingInterval, liqBase, liqDyn, σ_strict, brokerGas
    await pool.setNumbers(3600 * 8, rate("0.0001"), rate("0.0000"), rate("0.01"), toWei("0"))
    // mlpPrice, mlpPrice
    await pool.setEmergencyNumbers(toWei("1"), toWei("2000"))
    await pool.setLiquidityManager(liquidityManager.address, true)
    await mlp.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    usdc = await createContract("MockERC20", ["Usdc", "Usdc", 6])
    await usdc.mint(lp1.address, toUnit("1000000", 6))
    await usdc.mint(trader1.address, toUnit("100000", 6))

    wbtc = await createContract("MockERC20", ["Wbtc", "Wbtc", 18])
    await wbtc.mint(lp1.address, toWei("1000"))
    await wbtc.mint(trader1.address, toWei("100"))

    usdt = await createContract("MockERC20", ["Usdt", "Usdt", 12])
    await usdt.mint(lp1.address, toUnit("1000000", 12))
    await usdt.mint(trader1.address, toUnit("100000", 12))

    muxUsd = await createContract("MuxToken")
    await muxUsd.initialize("muxUsd", "muxUsd")
    await muxUsd.transfer(pool.address, toWei(PreMinedTokenTotalSupply))
    muxWbtc = await createContract("MuxToken")
    await muxWbtc.initialize("muxWbtc", "muxWbtc")
    await muxWbtc.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    // 0 = USDC
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("USDC"), 6, true, usdc.address, muxUsd.address)
    // id, symbol, imr, mmr, fee, fee, minBps, minTime, maxLong, maxShort, spotWeight, halfSpread
    await pool.setAssetParams(0, toBytes32("USDC"), rate("0"), rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1, rate("0"))
    // id, tradable, openable, shortable, useStable, enabled, strict, liq
    await pool.setAssetFlags(0, false, false, false, false, true, true, true)
    await pool.setFundingParams(0, rate("0.0002"), rate("0.0008"))

    // 1 = BTC
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(1, toBytes32("BTC"), 18, false, wbtc.address, muxWbtc.address)
    // id, symbol, imr, mmr, fee, fee, minBps, minTime, maxLong, maxShort, spotWeight, halfSpread
    await pool.setAssetParams(1, toBytes32("BTC"), rate("0.1"), rate("0.05"), rate("0.001"), rate("0.002"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2, rate("0"))
    // id, tradable, openable, shortable, useStable, enabled, strict, liq
    await pool.setAssetFlags(1, true, true, true, false, true, false, true)
    await pool.setFundingParams(1, rate("0.0003"), rate("0.0009"))

    // 2 = USDT
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(2, toBytes32("USDT"), 12, true, usdt.address, muxUsd.address)
    // id, symbol, imr, mmr, fee, fee, minBps, minTime, maxLong, maxShort, spotWeight, halfSpread
    await pool.setAssetParams(2, toBytes32("USDT"), rate("0"), rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1, rate("0"))
    // id, tradable, openable, shortable, useStable, enabled, strict, liq
    await pool.setAssetFlags(2, false, false, false, false, true, true, true)
    await pool.setFundingParams(2, rate("0.0002"), rate("0.0008"))

    await pool.setBlockTimestamp(86400 * 1)
    await orderBook.setBlockTimestamp(86400 * 1)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
    await pool.setBlockTimestamp(86400 * 2)
    await orderBook.setBlockTimestamp(86400 * 2)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.longCumulativeFundingRate).to.equal(toWei("0.0009")) // 0.0003 * 3
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("1.8")) // 0.0002 * 3 * 3000
    }
  })

  it("deposit, withdraw collateral when position = 0", async () => {
    // usdc
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      await expect(pool.depositCollateral(shortAccountId, toUnit("1000", 6))).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).depositCollateral(shortAccountId, toUnit("1000", 6))).to.revertedWith("SND")
      await expect(orderBook.connect(trader1).depositCollateral(shortAccountId, toUnit("0", 6))).to.revertedWith("C=0")
      const tx1 = await orderBook.connect(trader1).depositCollateral(shortAccountId, toUnit("1000", 6))
      const receipt1 = await tx1.wait()
      console.log("GAS short deposit", receipt1.gasUsed.toString(), tx1.hash)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000", 6))
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("1000"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
    }
    {
      await expect(pool.connect(trader1).withdrawAllCollateral(shortAccountId)).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).withdrawAllCollateral(shortAccountId)).to.revertedWith("SND")
      await orderBook.connect(trader1).withdrawAllCollateral(shortAccountId)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("0", 6))
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
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

  it("+/-liquidity, +/-trade", async () => {
    const current = toWei("29700")
    const target = toWei("29700")
    // +liq usdc
    await usdc.connect(lp1).approve(orderBook.address, toUnit("1000000", 6))
    {
      await pool.setBlockTimestamp(86400 * 2 + 0)
      await orderBook.setBlockTimestamp(86400 * 2 + 0)
      await expect(pool.connect(lp1).addLiquidity(lp1.address, 0, toUnit("1000000", 6), toWei("1"), toWei("1"), current, target)).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).placeLiquidityOrder(0, toUnit("0", 6), true)).to.revertedWith("A=0")
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
      const readerState = await reader.callStatic.getChainStorage()
      expect(readerState.lpDeduct).to.eq(toWei("1000000000000000000"))
      expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000"))
    }
    {
      await expect(orderBook.connect(broker).fillLiquidityOrder(0, toWei("1"), toWei("1000"), current, target)).to.revertedWith("LCK")
      await pool.setBlockTimestamp(86400 * 2 + 330)
      await orderBook.setBlockTimestamp(86400 * 2 + 330)
      await expect(orderBook.connect(lp1).fillLiquidityOrder(0, toWei("1"), toWei("1000"), current, target)).to.revertedWith("BKR")
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1"), toWei("1000"), current, target)
      const receipt1 = await tx1.wait()
      console.log("GAS +liq fill ", receipt1.gasUsed.toString(), tx1.hash)
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000000", 6))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999.9")) // fee = 100, (1000000 - fee) / 1000
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999000.1"))
      const readerState = await reader.callStatic.getChainStorage()
      expect(readerState.lpDeduct).to.eq(toWei("999999999999999000.1"))
      expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1000000"))
      expect(collateralInfo.collectedFee).to.equal(toWei("100"))
    }
    // -liq usdc
    await mlp.connect(lp1).approve(orderBook.address, toWei("1"))
    {
      await expect(pool.connect(lp1).removeLiquidity(lp1.address, toWei("1"), 0, toWei("1"), toWei("1"), current, target)).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).placeLiquidityOrder(0, toWei("0"), false)).to.revertedWith("A=0")
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(0, toWei("1"), false)
      const receipt1 = await tx1.wait()
      console.log("GAS -liq order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 1, 0, toWei("1"), false)
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("998.9"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("1"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999000.1"))
      const readerState = await reader.callStatic.getChainStorage()
      expect(readerState.lpDeduct).to.eq(toWei("999999999999999000.1"))
      expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000"))
    }
    {
      await expect(orderBook.connect(broker).fillLiquidityOrder(1, toWei("1"), toWei("2000"), current, target)).to.revertedWith("LCK")
      await pool.setBlockTimestamp(86400 * 2 + 660)
      await orderBook.setBlockTimestamp(86400 * 2 + 660)
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(1, toWei("1"), toWei("2000"), current, target)
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
      const readerState = await reader.callStatic.getChainStorage()
      expect(readerState.lpDeduct).to.eq(toWei("999999999999999001.1"))
      expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000"))
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
      await expect(orderBook.connect(broker).fillLiquidityOrder(2, toWei("1000"), toWei("1000"), current, target)).to.revertedWith("LCK")
      await pool.setBlockTimestamp(86400 * 2 + 990)
      await orderBook.setBlockTimestamp(86400 * 2 + 990)
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(2, toWei("1000"), toWei("1000"), current, target)
      const receipt1 = await tx1.wait()
      expect(await wbtc.balanceOf(lp1.address)).to.equal(toWei("900"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("1098.89")) // (100 - fee) * 1000 / 1000
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999998901.11"))
      const collateralInfo = await pool.getAssetInfo(1)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("100")) // fee = 0.01
      expect(collateralInfo.collectedFee).to.equal(toWei("0.01"))
    }
    // open short btc, using usdc
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      await expect(pool.connect(trader1).openPosition(shortAccountId, toWei("1"), toWei("1000"), toWei("1"))).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).placePositionOrder2(shortAccountId, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode)).to.revertedWith(
        "SND"
      )
      await expect(
        orderBook.connect(trader1).placePositionOrder2(shortAccountId, toUnit("1000", 6), toWei("0"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode)
      ).to.revertedWith("S=0")
      const tx1 = await orderBook.connect(trader1).placePositionOrder2(shortAccountId, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode)
      const receipt1 = await tx1.wait()
      console.log("GAS +sht order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(shortAccountId, 3, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("998000.2"))
      expect(collateralInfo.collectedFee).to.equal(toWei("100.2"))
    }
    {
      await expect(orderBook.connect(trader1).fillPositionOrder(3, toWei("1"), toWei("2000"), toWei("0"))).to.revertedWith("BKR")
      await expect(orderBook.connect(broker).fillPositionOrder(3, toWei("1"), toWei("999"), toWei("0"))).to.revertedWith("LMT")
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
      expect(subAccount.entryFunding).to.equal(toWei("1.8")) // 0.0006 * 3000
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("998002.2"))
      expect(collateralInfo.collectedFee).to.equal(toWei("102.2"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
    await expect(orderBook.connect(lp1).withdrawAllCollateral(shortAccountId)).to.revertedWith("SND")
    await expect(orderBook.connect(trader1).withdrawAllCollateral(shortAccountId)).to.revertedWith("S>0")
    // open long btc, using wbtc
    const longAccountId = assembleSubAccountId(trader1.address, 1, 1, true)
    await wbtc.connect(trader1).approve(orderBook.address, toWei("10"))
    {
      const tx1 = await orderBook.connect(trader1).placePositionOrder2(longAccountId, toWei("10"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode)
      const receipt1 = await tx1.wait()
      console.log("GAS +lng order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 4, toWei("10"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("90"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("10"))
    }
    {
      await expect(orderBook.connect(broker).fillPositionOrder(4, toWei("3001"), toWei("3001"), toWei("0"))).to.revertedWith("LMT")
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
    // update funding
    await pool.setBlockTimestamp(86400 * 3)
    await orderBook.setBlockTimestamp(86400 * 3)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.longCumulativeFundingRate).to.equal(toWei("0.0018")) // 0.0009 + 0.0003 * 3
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("3.6")) // 1.8 + 0.0002 * 3 * 3000
    }
    // close short, profit in usdc, auto withdraw all
    {
      await expect(pool.connect(trader1).closePosition(shortAccountId, toWei("1"), 0, toWei("1"), toWei("1900"), toWei("1"))).to.revertedWith("BOK")
      await expect(
        orderBook.connect(lp1).placePositionOrder2(shortAccountId, toUnit("0", 6), toWei("1"), toWei("1950"), 0, PositionOrderFlags.WithdrawAllIfEmpty, 86400 * 100, refCode)
      ).to.revertedWith("SND")
      const tx1 = await orderBook.connect(trader1).placePositionOrder2(shortAccountId, toUnit("0", 6), toWei("1"), toWei("1950"), 0, PositionOrderFlags.WithdrawAllIfEmpty, 86400 * 100, refCode)
      const receipt1 = await tx1.wait()
      console.log("GAS -sht order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(shortAccountId, 5, toUnit("0", 6), toWei("1"), toWei("1950"), 0, PositionOrderFlags.WithdrawAllIfEmpty, 86400 * 100)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999000.2", 6))
    }
    {
      await expect(orderBook.connect(broker).fillPositionOrder(5, toWei("1"), toWei("1960"), toWei("1"))).to.revertedWith("LMT")
      const tx1 = await orderBook.connect(broker).fillPositionOrder(5, toWei("1"), toWei("1900"), toWei("1")) // pnl = 100
      const receipt1 = await tx1.wait()
      console.log("GAS -sht fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100094.3", 6)) // funding fee = (3.6 - 1.8) * 1, pos fee = 1.9, 99000 + 100 - fee + 998
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("997905.9", 6)) // 999000.2 - (100 - fee + 998)
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("997905.9"))
      expect(collateralInfo.collectedFee).to.equal(toWei("105.9")) // 102.2 + fee
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    // close long, profit in wbtc, partial withdraw
    {
      const tx1 = await orderBook.connect(trader1).placePositionOrder2(longAccountId, toWei("1"), toWei("1"), toWei("1000"), 0, 0, 86400 * 100, refCode)
      const receipt1 = await tx1.wait()
      console.log("GAS -lng order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 6, toWei("1"), toWei("1"), toWei("1000"), 0, 0, 86400 * 100)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("90"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("110"))
    }
    {
      await expect(orderBook.connect(broker).fillPositionOrder(6, toWei("999"), toWei("999"), toWei("999"))).to.revertedWith("LMT")
      const tx1 = await orderBook.connect(broker).fillPositionOrder(6, toWei("2100"), toWei("2100"), toWei("2100")) // pnl = 100
      const receipt1 = await tx1.wait()
      console.log("GAS -lng fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("91.045719047619047619")) // funding fee = 0.0009, pos fee = 0.001, 90 + 100/2100 - fee + withdraw
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("108.954280952380952381")) // 110 - (withdraw + 100/2100 - fee)
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("8.999")) // 9.999 - withdraw
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("99.955280952380952381")) // 100.001 - pnl + fee
      expect(assetInfo.collectedFee).to.equal(toWei("0.0129"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
  })

  it("stop loss", async () => {
    // open long btc, using wbtc
    const longAccountId = assembleSubAccountId(trader1.address, 1, 1, true)
    await wbtc.connect(trader1).approve(orderBook.address, toWei("10"))
    {
      await expect(await orderBook.connect(trader1).placePositionOrder2(longAccountId, toWei("10"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode))
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 0, toWei("10"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("90"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("10"))
    }
    {
      await orderBook.connect(broker).fillPositionOrder(0, toWei("2000"), toWei("2000"), toWei("0"))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("9.999")) // fee = 0.001
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("0.001"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.001"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    // close long, profit in wbtc
    {
      await expect(orderBook.connect(trader1).placePositionOrder2(longAccountId, toWei("0"), toWei("1"), toWei("1999"), 0, PositionOrderFlags.TriggerOrder, 86400 * 100, refCode))
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 1, toWei("0"), toWei("1"), toWei("1999"), 0, PositionOrderFlags.TriggerOrder, 86400 * 100)
    }
    {
      await expect(orderBook.connect(broker).fillPositionOrder(1, toWei("2000"), toWei("2000"), toWei("2000"))).to.revertedWith("LMT")
      await orderBook.connect(broker).fillPositionOrder(1, toWei("1999"), toWei("1999"), toWei("1999")) // pnl = -1
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("90"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("10")) // did not withdraw
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("9.997499749874937469")) // funding fee = 0, pos fee = 0.001, 9.999 - 1/1999 - fee
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("0.002500250125062531")) // - pnl + fee
      expect(assetInfo.collectedFee).to.equal(toWei("0.002"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
  })

  it("liquidate", async () => {
    // open short btc, using usdc
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      await expect(orderBook.connect(trader1).placePositionOrder2(shortAccountId, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode))
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(shortAccountId, 0, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100)
      await orderBook.connect(broker).fillPositionOrder(0, toWei("1"), toWei("2000"), toWei("0"))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000", 6))
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("1.8")) // 0.0006 * 3000
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("2"))
      expect(collateralInfo.collectedFee).to.equal(toWei("2"))
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
      await expect(orderBook.connect(trader1).placePositionOrder2(longAccountId, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode))
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 1, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100)
      await orderBook.connect(broker).fillPositionOrder(1, toWei("2000"), toWei("2000"), toWei("0"))
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("99.5"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("0.5"))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("0.499")) // fee = 0.001
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("0.001"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.001"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    // update funding
    await pool.setBlockTimestamp(86400 * 3)
    await orderBook.setBlockTimestamp(86400 * 3)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.longCumulativeFundingRate).to.equal(toWei("0.0018")) // 0.0009 + 0.0003 * 3
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("3.6")) // 1.8 + 0.0002 * 3 * 3000
    }
    // liquidate short
    {
      await orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("1"), toWei("2860"), toWei("1"))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99130.48", 6)) // funding fee = (3.6 - 1.8) * 1, pos fee = 5.72, pnl = -860, collateral = 998 + pnl - fee. erc20 = 99000 + collateral
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("869.52", 6)) // previousCollectedFee - pnl + fee
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("869.52"))
      expect(collateralInfo.collectedFee).to.equal(toWei("9.52"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    // liquidate long
    {
      await orderBook.connect(broker).liquidate(longAccountId, 1, toWei("1380"), toWei("1380"), toWei("1380")) // pnl = -620 / 1380
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("99.546824637681159421")) // funding fee = 0.0009, pos fee = 0.002, collateral = 0.499 + pnl - fee. erc20 = 99.5 + collateral
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("0.453175362318840579")) // previousCollectedFee - pnl + fee
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("0.453175362318840579"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.0039"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
  })

  it("liquidate - unsafe caused by funding payment", async () => {
    // open long btc, using wbtc
    const longAccountId = assembleSubAccountId(trader1.address, 1, 1, true)
    await wbtc.connect(trader1).approve(orderBook.address, toWei("10"))
    {
      await expect(orderBook.connect(trader1).placePositionOrder2(longAccountId, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode))
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 0, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100)
      await orderBook.connect(broker).fillPositionOrder(0, toWei("2000"), toWei("2000"), toWei("0"))
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("99.5"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("0.5"))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("0.499")) // fee = 0.001
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("0.001"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.001"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    // safe before funding payment
    {
      await expect(orderBook.connect(broker).liquidate(longAccountId, 1, toWei("1380.6433798"), toWei("1380.6433798"), toWei("1380.6433798"))).to.revertedWith("MMS")
    }
    // update funding
    await pool.setBlockTimestamp(86400 * 3)
    await orderBook.setBlockTimestamp(86400 * 3)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.longCumulativeFundingRate).to.equal(toWei("0.0018")) // 0.0009 + 0.0003 * 3
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("3.6")) // 1.8 + 0.0002 * 3 * 3000
    }
    // liquidate long
    {
      await orderBook.connect(broker).liquidate(longAccountId, 1, toWei("1380.6433798"), toWei("1380.6433798"), toWei("1380.6433798")) // pnl = -0.44860000001573179600017084730
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("99.547499999984268204")) // funding fee = 0.0009, pos fee = 0.002, collateral = 0.499 + pnl - fee. erc20 = 99.5 + collateral
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("0.452500000015731796")) // previousCollectedFee - pnl + fee
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("0.452500000015731796"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.0039"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
  })

  it("liquidate - change mm rate", async () => {
    // open short btc, using usdc
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      await expect(orderBook.connect(trader1).placePositionOrder2(shortAccountId, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode))
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(shortAccountId, 0, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100)
      await orderBook.connect(broker).fillPositionOrder(0, toWei("1"), toWei("2000"), toWei("0"))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000", 6))
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("1.8")) // 0.0006 * 3000
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("2"))
      expect(collateralInfo.collectedFee).to.equal(toWei("2"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
    // update funding
    await pool.setBlockTimestamp(86400 * 3)
    await orderBook.setBlockTimestamp(86400 * 3)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.longCumulativeFundingRate).to.equal(toWei("0.0018")) // 0.0009 + 0.0003 * 3
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("3.6")) // 1.8 + 0.0002 * 3 * 3000
    }
    // change mm rate
    await expect(orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("1"), toWei("1996"), toWei("1"))).to.revertedWith("MMS")
    // id, symbol, imr, mmr, fee, fee, minBps, minTime, maxLong, maxShort, spotWeight, halfSpread
    await pool.setAssetParams(1, toBytes32("BTC"), rate("0.70"), rate("0.60"), rate("0.001"), rate("0.002"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2, rate("0"))

    // liquidate short
    {
      await orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("1"), toWei("1996"), toWei("1"))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99996.208", 6)) // funding fee = (3.6 - 1.8) * 1, pos fee = 3.992, pnl = +4, collateral = 998 + pnl - fee. erc20 = 99000 + collateral
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("3.792", 6)) // previousCollectedFee - pnl + fee
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("3.792"))
      expect(collateralInfo.collectedFee).to.equal(toWei("7.792"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
  })

  it("withdraw", async () => {
    // open long btc, using usdc
    const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
    // deposit
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      await orderBook.connect(trader1).depositCollateral(longAccountId, toUnit("1000", 6))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000", 6))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("1000"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
    }
    // open long
    {
      await expect(orderBook.connect(trader1).placePositionOrder2(longAccountId, toWei("0"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode))
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 0, toWei("0"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
    }
    {
      await orderBook.connect(broker).fillPositionOrder(0, toWei("1"), toWei("2000"), toWei("0"))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000", 6))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("0"))
      expect(assetInfo.collectedFee).to.equal(toWei("0"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("2"))
      expect(collateralInfo.collectedFee).to.equal(toWei("2"))
    }
    // update funding
    await pool.setBlockTimestamp(86400 * 3)
    await orderBook.setBlockTimestamp(86400 * 3)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.longCumulativeFundingRate).to.equal(toWei("0.0018")) // 0.0009 + 0.0003 * 3
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("3.6")) // 1.8 + 0.0002 * 3 * 3000
    }
    // withdraw collateral
    {
      await expect(orderBook.connect(trader1).placeWithdrawalOrder(longAccountId, toUnit("0", 6), 0, false)).to.revertedWith("A=0")
      await expect(orderBook.connect(trader1).placeWithdrawalOrder(longAccountId, toUnit("1", 6), 0, false))
        .to.emit(orderBook, "NewWithdrawalOrder")
        .withArgs(longAccountId, 1, toUnit("1", 6), 0, false)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000", 6))
    }
    {
      await expect(orderBook.connect(trader1).fillWithdrawalOrder(1, toWei("1"), toWei("2100"), toWei("0"))).to.revertedWith("BKR")
      await orderBook.connect(broker).fillWithdrawalOrder(1, toWei("1"), toWei("2100"), toWei("0"))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99001", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999", 6))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("995.11")) // funding fee = 0.0009 * 2100 * 1 = 1.89. 998 - funding - withdraw
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0018"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("0"))
      expect(assetInfo.collectedFee).to.equal(toWei("0"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
      expect(assetInfo.spotLiquidity).to.equal(toWei("0"))
      expect(assetInfo.collectedFee).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("3.89"))
      expect(collateralInfo.collectedFee).to.equal(toWei("3.89"))
    }
    // +liq wbtc
    await wbtc.connect(lp1).approve(orderBook.address, toWei("100"))
    {
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(1, toWei("100"), true)
      const receipt1 = await tx1.wait()
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 2, 1, toWei("100"), true)
    }
    // update funding
    await pool.setBlockTimestamp(86400 * 4)
    await orderBook.setBlockTimestamp(86400 * 4)
    await orderBook.connect(broker).updateFundingState(rate("0"), [1], [rate("0")], [toWei("3000")])
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.longCumulativeFundingRate).to.equal(toWei("0.0027")) // 0.0018 + 0.0003 * 3
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("5.4")) // 3.6 + 0.0002 * 3 * 3000
    }
    {
      const current = toWei("29700")
      const target = toWei("29700")
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(2, toWei("2000"), toWei("1"), current, target)
      const receipt1 = await tx1.wait()
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("100"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.spotLiquidity).to.equal(toWei("100")) // fee = 0.01
      expect(assetInfo.collectedFee).to.equal(toWei("0.01"))
    }
    // withdraw profit
    {
      await expect(orderBook.connect(trader1).placeWithdrawalOrder(longAccountId, toWei("0"), 0, true)).to.revertedWith("A=0")
      await expect(orderBook.connect(trader1).placeWithdrawalOrder(longAccountId, toWei("0.01"), 0, true))
        .to.emit(orderBook, "NewWithdrawalOrder")
        .withArgs(longAccountId, 3, toWei("0.01"), 0, true)
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("100"))
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("100"))
    }
    {
      await expect(orderBook.connect(trader1).fillWithdrawalOrder(3, toWei("1"), toWei("2100"), toWei("0"))).to.revertedWith("BKR")
      await orderBook.connect(broker).fillWithdrawalOrder(3, toWei("1"), toWei("2100"), toWei("0")) // original pnl = (2100 - 2000) * 1 = 100
      expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("100.01")) // funding fee = 0.0009 * 1
      expect(await wbtc.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("99.99"))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("995.11"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2022.89")) // withdraw + fee = 0.01 * 2100 + 0.0009 * 2100 = 22.89. new pnl = (2100 - 2022.89) * 1 = 77.11
      expect(subAccount.entryFunding).to.equal(toWei("0.0027"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2022.89"))
      expect(assetInfo.spotLiquidity).to.equal(toWei("99.99"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.0109"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("3.89"))
      expect(collateralInfo.collectedFee).to.equal(toWei("3.89"))
    }
  })

  function makeCallContext1(methodId: string, paramTypes: any, params: any, dexId: number = 0) {
    return {
      methodId: toBytes32(methodId),
      params: paramTypes.length == 0 ? "0x" : U.defaultAbiCoder.encode(paramTypes, params),
      dexId: dexId,
    }
  }

  describe("muxToken", async () => {
    const current = toWei("29700")
    const target = toWei("29700")

    beforeEach(async () => {
      // +liq wbtc
      await wbtc.connect(lp1).approve(orderBook.address, toWei("100"))
      {
        await orderBook.connect(lp1).placeLiquidityOrder(1, toWei("100"), true)
        await pool.setBlockTimestamp(86400 * 2 + 990)
        await orderBook.setBlockTimestamp(86400 * 2 + 990)
        await orderBook.connect(broker).fillLiquidityOrder(0, toWei("2000"), toWei("1"), current, target)
        expect(await wbtc.balanceOf(lp1.address)).to.equal(toWei("900"))
        expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("100"))
        expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("199980")) // (100 - fee) * 2000 / 1
        expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999800020"))
        const collateralInfo = await pool.getAssetInfo(1)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("100")) // fee = 0.01
        expect(collateralInfo.collectedFee).to.equal(toWei("0.01"))
      }
      // withdraw 100 wbtc from LiquidityPool to LiquidityManager
      {
        await liquidityManager.addDexSpotConfiguration(1, 0, 100, [1], [1])
        const testPlugin = await createContract("TestPlugin")
        await liquidityManager.setPlugin(testPlugin.address, true)
        const tmp = await ethers.getContractAt("TestPlugin", liquidityManager.address)
        await tmp.pullAssets([1], [toWei("100")])

        const collateralInfo = await pool.getAssetInfo(1)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("0"))
        expect(collateralInfo.collectedFee).to.equal(toWei("0.01"))
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999800020")) // lp supply = 199980
        expect(readerState.assets[1].deduct).to.eq(toWei("1000000000000000000")) // muxBTC supply = 0
        expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000")) // muxUSD supply = 0
      }
    })

    it("close long, profit in muxBtc, and redeem muxBtc", async () => {
      // open long
      const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
      await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
      {
        await orderBook.connect(trader1).placePositionOrder2(longAccountId, toUnit("1000", 6), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode)
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
        expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("100"))
        await orderBook.connect(broker).fillPositionOrder(1, toWei("1"), toWei("2000"), toWei("0"))
        const subAccount = await pool.getSubAccount(longAccountId)
        expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
        expect(subAccount.size).to.equal(toWei("1"))
        expect(subAccount.entryPrice).to.equal(toWei("2000"))
        expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("2"))
        expect(collateralInfo.collectedFee).to.equal(toWei("2"))
        const assetInfo = await pool.getAssetInfo(1)
        expect(assetInfo.spotLiquidity).to.equal(toWei("0"))
        expect(assetInfo.collectedFee).to.equal(toWei("0.01"))
      }
      // close long, profit in muxBtc, auto withdraw all
      {
        await orderBook.connect(trader1).placePositionOrder2(longAccountId, toUnit("0", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.WithdrawAllIfEmpty, 86400 * 100, refCode)
        await orderBook.connect(broker).fillPositionOrder(2, toWei("1"), toWei("2100"), toWei("1")) // pnl = 100, funding fee = 0, pos fee = 0.001
        expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("100")) // collateral + [1].spotLiquidity
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99998", 6)) // 99000 + 998
        expect(await muxWbtc.balanceOf(trader1.address)).to.equal(toWei("0.046619047619047619")) // += pnl / mark - fee - [1].spotLiquidity
        const subAccount = await pool.getSubAccount(longAccountId)
        expect(subAccount.collateral).to.equal(toWei("0"))
        expect(subAccount.size).to.equal(toWei("0"))
        expect(subAccount.entryPrice).to.equal(toWei("0"))
        expect(subAccount.entryFunding).to.equal(toWei("0"))
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("2"))
        expect(collateralInfo.collectedFee).to.equal(toWei("2"))
        const assetInfo = await pool.getAssetInfo(1)
        expect(assetInfo.spotLiquidity).to.equal(toWei("0"))
        expect(assetInfo.collectedFee).to.equal(toWei("0.011")) // += fee
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999800020")) // lp supply = 199980
        expect(readerState.assets[1].deduct).to.eq(toWei("999999999999999999.953380952380952381")) // muxWbtc supply = 0.046619047619047619
        expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000")) // muxUsd supply = 0
      }
      // deposit 1 wbtc from LiquidityManager to LiquidityPool
      {
        // const testPlugin = await createContract("TestPlugin")
        // await liquidityManager.setPlugin(testPlugin.address, true)
        const tmp = await ethers.getContractAt("TestPlugin", liquidityManager.address)
        await tmp.pushAssets([1], [toWei("1")])

        expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("1"))
        const assetInfo = await pool.getAssetInfo(1)
        expect(assetInfo.spotLiquidity).to.equal(toWei("1"))
        expect(assetInfo.collectedFee).to.equal(toWei("0.011")) // += fee
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999800020")) // lp supply = 199980
        expect(readerState.assets[1].deduct).to.eq(toWei("999999999999999999.953380952380952381")) // muxWbtc supply = 0.046619047619047619
        expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000")) // muxUSD supply = 0
      }
      // redeem muxBtc
      await muxWbtc.connect(trader1).approve(orderBook.address, toWei("0.046619047619047619"))
      {
        await orderBook.connect(trader1).redeemMuxToken(1, toWei("0.046619047619047619"))
        expect(await wbtc.balanceOf(trader1.address)).to.equal(toWei("100.046619047619047619"))
        expect(await wbtc.balanceOf(pool.address)).to.equal(toWei("0.953380952380952381")) // 1 - 0.046619047619047619
        expect(await muxWbtc.balanceOf(trader1.address)).to.equal(toWei("0"))
        expect(await muxWbtc.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))
        const assetInfo = await pool.getAssetInfo(1)
        expect(assetInfo.spotLiquidity).to.equal(toWei("0.953380952380952381"))
        expect(assetInfo.collectedFee).to.equal(toWei("0.011")) // += fee
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999800020")) // lp supply = 199980
        expect(readerState.assets[1].deduct).to.eq(toWei("1000000000000000000")) // muxWbtc supply = 0
        expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000")) // muxUSD supply = 0
      }
    })

    it("close short (collateral usdc), profit in muxUsd, redeem to usdt", async () => {
      // +liq usdt
      await usdt.connect(lp1).approve(orderBook.address, toUnit("10000", 12))
      {
        await orderBook.connect(lp1).placeLiquidityOrder(2, toUnit("10000", 12), true)
        await pool.setBlockTimestamp(86400 * 2 + 1320)
        await orderBook.setBlockTimestamp(86400 * 2 + 1320)
        await orderBook.connect(broker).fillLiquidityOrder(1, toWei("1"), toWei("1"), current, target) // fee = 1
        expect(await usdt.balanceOf(pool.address)).to.equal(toUnit("10000", 12))
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("0"))
        expect(collateralInfo.collectedFee).to.equal(toWei("0"))
        const collateral2Info = await pool.getAssetInfo(2)
        expect(collateral2Info.spotLiquidity).to.equal(toWei("10000"))
        expect(collateral2Info.collectedFee).to.equal(toWei("1"))
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999790021")) // lp supply = 209979
        expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000")) // muxUSD supply = 0
      }
      // open short
      const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
      await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
      {
        await orderBook.connect(trader1).placePositionOrder2(shortAccountId, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode)
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
        expect(await usdt.balanceOf(trader1.address)).to.equal(toUnit("100000", 12))
        await orderBook.connect(broker).fillPositionOrder(2, toWei("1"), toWei("2000"), toWei("0"))
        const subAccount = await pool.getSubAccount(shortAccountId)
        expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
        expect(subAccount.size).to.equal(toWei("1"))
        expect(subAccount.entryPrice).to.equal(toWei("2000"))
        expect(subAccount.entryFunding).to.equal(toWei("1.8")) // 0.0006 * 3000
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("2"))
        expect(collateralInfo.collectedFee).to.equal(toWei("2"))
        const collateral2Info = await pool.getAssetInfo(2)
        expect(collateral2Info.spotLiquidity).to.equal(toWei("10000"))
        expect(collateral2Info.collectedFee).to.equal(toWei("1"))
      }
      // close short, profit in usdc (muxUsd), auto withdraw all
      {
        await orderBook.connect(trader1).placePositionOrder2(shortAccountId, toUnit("0", 6), toWei("1"), toWei("3000"), 0, PositionOrderFlags.WithdrawAllIfEmpty, 86400 * 100, refCode)
        await orderBook.connect(broker).fillPositionOrder(3, toWei("1"), toWei("1900"), toWei("1")) // pnl = 100, fee = 1.9
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100000", 6)) // += collateral + [0].spotLiquidity
        expect(await usdt.balanceOf(trader1.address)).to.equal(toUnit("100000", 12)) // += 0
        expect(await muxUsd.balanceOf(trader1.address)).to.equal(toWei("96.1")) // += pnl - fee - [0].spotLiquidity
        const subAccount = await pool.getSubAccount(shortAccountId)
        expect(subAccount.collateral).to.equal(toWei("0"))
        expect(subAccount.size).to.equal(toWei("0"))
        expect(subAccount.entryPrice).to.equal(toWei("0"))
        expect(subAccount.entryFunding).to.equal(toWei("0"))
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("0"))
        expect(collateralInfo.collectedFee).to.equal(toWei("3.9")) // += fee
        const collateral2Info = await pool.getAssetInfo(2)
        expect(collateral2Info.spotLiquidity).to.equal(toWei("10000"))
        expect(collateral2Info.collectedFee).to.equal(toWei("1"))
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999790021")) // lp supply = 209979
        expect(readerState.stableDeduct).to.eq(toWei("999999999999999903.9")) // muxUsd supply = 96.1
      }
      // redeem muxUsd into usdt
      await muxUsd.connect(trader1).approve(orderBook.address, toWei("96.1"))
      {
        await orderBook.connect(trader1).redeemMuxToken(2, toWei("96.1"))
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100000", 6))
        expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("0", 6))
        expect(await usdt.balanceOf(trader1.address)).to.equal(toUnit("100096.1", 12)) // += 96.1
        expect(await usdt.balanceOf(pool.address)).to.equal(toUnit("9903.9", 12))
        expect(await muxUsd.balanceOf(trader1.address)).to.equal(toWei("0"))
        expect(await muxUsd.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("0"))
        expect(collateralInfo.collectedFee).to.equal(toWei("3.9")) // += fee
        const collateral2Info = await pool.getAssetInfo(2)
        expect(collateral2Info.spotLiquidity).to.equal(toWei("9903.9")) // -= 96.1
        expect(collateral2Info.collectedFee).to.equal(toWei("1"))
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999790021")) // lp supply = 209979
        expect(readerState.stableDeduct).to.eq(toWei("1000000000000000000")) // muxUsd supply = 0
      }
    })
  })
})
