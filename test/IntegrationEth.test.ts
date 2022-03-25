import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { BigNumber, Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, rate, PreMinedTokenTotalSupply, createFactory } from "./deployUtils"
import { createContract, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { MlpToken, OrderBook, TestLiquidityPool, LiquidityManager, MockERC20 } from "../typechain"
const U = ethers.utils

describe("IntegrationEth", () => {
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let orderBook: OrderBook
  let liquidityManager: LiquidityManager
  let weth9: MockERC20
  let muxWeth: Contract

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
    weth9 = (await createContract("WETH9")) as MockERC20
    await orderBook.initialize(pool.address, mlp.address, weth9.address)
    await orderBook.addBroker(broker.address)
    await liquidityManager.initialize(pool.address)
    await pool.initialize(poolHop2.address, mlp.address, orderBook.address, liquidityManager.address, weth9.address)
    // fundingInterval, liquidityLockPeriod
    await pool.setNumbers(8 * 3600, 5 * 60)
    await mlp.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    muxWeth = await createContract("MuxToken", ["muxWeth", "muxWeth"])
    await muxWeth.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    // 0 = ETH
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("ETH"), 18, false, weth9.address, muxWeth.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setAssetParams(
      0,
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
    await pool.setAssetFlags(0, true, true, true, false)
    await pool.setFundingParams(0, rate("0.0003"), rate("0.0009"))

    await pool.setBlockTimestamp(86400 * 1)
    await orderBook.connect(broker).updateFundingState(rate("0"), [0], [rate("0")])
    await pool.setBlockTimestamp(86400 * 2)
    await orderBook.connect(broker).updateFundingState(rate("0"), [0], [rate("0")])
  })

  it("deposit, withdraw collateral when position = 0", async () => {
    // weth
    const longAccountId = assembleSubAccountId(trader1.address, 0, 0, true)
    const initBalance = await ethers.provider.getBalance(trader1.address)
    {
      const tx1 = await orderBook.connect(trader1).depositCollateral(longAccountId, toWei("10"), { value: toWei("10") })
      const receipt1 = await tx1.wait()
      console.log("GAS long  deposit", receipt1.gasUsed.toString(), tx1.hash)
      expect(await ethers.provider.getBalance(orderBook.address)).to.equal(toWei("0"))
      expect(await ethers.provider.getBalance(pool.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("10"))
    }
    {
      await pool.connect(trader1).withdrawAllCollateral(longAccountId)
      expect(await ethers.provider.getBalance(orderBook.address)).to.equal(toWei("0"))
      expect(await ethers.provider.getBalance(pool.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(trader1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("0"))
    }
  })
  it("most commonly used functions", async () => {
    // +liq eth
    {
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(0, toWei("100"), true, { value: toWei("100") })
      const receipt1 = await tx1.wait()
      console.log("GAS +liq order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 0, 0, toWei("100"), true)
      expect(await weth9.balanceOf(lp1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("100"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("0"))
    }
    {
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1000"), toWei("1000"), rate("0.0001"))
      const receipt1 = await tx1.wait()
      console.log("GAS +liq fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await weth9.balanceOf(lp1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("100")) // fee = 0.01
      expect(collateralInfo.collectedFee).to.equal(toWei("0.01"))
    }
    {
      await pool.setBlockTimestamp(86400 * 2 + 600)
      await pool.connect(lp1).claimMLP()
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("99.99")) // (100 - fee) * 1000 / 1000
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999900.01"))
    }
    // -liq eth
    await mlp.connect(lp1).approve(orderBook.address, toWei("1"))
    {
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(0, toWei("1"), false)
      const receipt1 = await tx1.wait()
      console.log("GAS -liq order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 1, 0, toWei("1"), false)
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("98.99"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("1"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999900.01"))
    }
    {
      const balance1 = await ethers.provider.getBalance(lp1.address)
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(1, toWei("1000"), toWei("2000"), rate("0.0001"))
      const receipt1 = await tx1.wait()
      console.log("GAS -liq fill ", receipt1.gasUsed.toString(), tx1.hash)
      const balance2 = await ethers.provider.getBalance(lp1.address)
      expect(balance2.sub(balance1).gt(toWei("1.99"))).to.true // fee = 0.0002, (1 * 2000) / 1000 - fee = 1.9998
      expect(balance2.sub(balance1).lte(toWei("1.9998"))).to.true
      expect(await weth9.balanceOf(lp1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("98.0002"))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("98.99"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999901.01"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("98.0002"))
      expect(collateralInfo.collectedFee).to.equal(toWei("0.0102"))
    }
    // open long eth, using eth
    const longAccountId = assembleSubAccountId(trader1.address, 0, 0, true)
    {
      const tx1 = await orderBook
        .connect(trader1)
        .placePositionOrder(longAccountId, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, { value: toWei("0.5") })
      const receipt1 = await tx1.wait()
      console.log("GAS +lng order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 2, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition)
      expect(await weth9.balanceOf(trader1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0.5"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("98.0002"))
    }
    {
      const tx1 = await orderBook.connect(broker).fillPositionOrder(2, toWei("2000"), toWei("2000"), toWei("0"))
      const receipt1 = await tx1.wait()
      console.log("GAS +lng fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await weth9.balanceOf(trader1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("98.5002"))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("0.499")) // fee = 0.001
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("98.0012"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.0112"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    // close long, profit in eth
    {
      const tx1 = await orderBook
        .connect(trader1)
        .placePositionOrder(longAccountId, toWei("0"), toWei("1"), toWei("1000"), 0, PositionOrderFlags.WithdrawAllIfEmpty)
      const receipt1 = await tx1.wait()
      console.log("GAS -lng order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 3, toWei("0"), toWei("1"), toWei("1000"), 0, PositionOrderFlags.WithdrawAllIfEmpty)
      expect(await weth9.balanceOf(trader1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("98.5002"))
    }
    {
      const balance1 = await ethers.provider.getBalance(trader1.address)
      const tx1 = await orderBook.connect(broker).fillPositionOrder(3, toWei("2100"), toWei("2100"), toWei("2100")) // pnl = 100
      const receipt1 = await tx1.wait()
      console.log("GAS -lng fill ", receipt1.gasUsed.toString(), tx1.hash)
      const balance2 = await ethers.provider.getBalance(trader1.address)
      expect(balance2.sub(balance1).gt(toWei("0.54"))).to.true // fee = 0.001, 0.499 + 100/2100 - fee = 0.54561904761904761904761904761905
      expect(balance2.sub(balance1).lte(toWei("0.545619047619047619"))).to.true
      expect(await weth9.balanceOf(trader1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("97.954580952380952381")) // 98.5002 - (0.499 + 100/2100 - fee)
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("97.954580952380952381")) // 98.0012 + 0.001 - 100/2100
      expect(assetInfo.collectedFee).to.equal(toWei("0.0122"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
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
