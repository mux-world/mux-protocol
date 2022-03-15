import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import {
  toWei,
  toUnit,
  toBytes32,
  rate,
  PreMinedTokenTotalSupply,
  AdminParamsType,
  AdminParamsAbi,
} from "./deployUtils"
import { createContract, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { MlpToken, OrderBook, TestLiquidityPool, LiquidityManager } from "../typechain"
const U = ethers.utils

describe("Integration", () => {
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let orderBook: OrderBook
  let liquidityManager: LiquidityManager
  let usdc: Contract
  let weth: Contract
  let muxUsdc: Contract
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
    mlp = (await createContract("MlpToken")) as MlpToken
    const LibMuxAdmin = await createContract("LibMuxAdmin")
    pool = (await createContract("TestLiquidityPool", [], { LibMuxAdmin })) as TestLiquidityPool
    orderBook = (await createContract("OrderBook")) as OrderBook
    liquidityManager = (await createContract("LiquidityManager")) as LiquidityManager
    await orderBook.initialize(pool.address, mlp.address)
    await orderBook.addBroker(broker.address)
    await liquidityManager.initialize(pool.address)
    await pool.initialize(mlp.address)
    await pool.setParams(
      AdminParamsType.SetAddresses,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAddresses, [orderBook.address, liquidityManager.address])
    )
    await mlp.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    usdc = await createContract("MockERC20", ["USDC", "USDC", 6])
    await usdc.mint(lp1.address, toUnit("1000000", 6))
    await usdc.mint(trader1.address, toUnit("100000", 6))

    weth = await createContract("MockERC20", ["WETH", "WETH", 18])
    await weth.mint(lp1.address, toWei("1000"))
    await weth.mint(trader1.address, toWei("100"))

    muxUsdc = await createContract("MuxToken", ["muxUsdc", "muxUsdc"])
    await muxUsdc.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    muxWeth = await createContract("MuxToken", ["muxWeth", "muxWeth"])
    await muxWeth.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    // id, symbol, decimals, stable, token, pool
    await pool.setParams(
      AdminParamsType.AddAsset,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.AddAsset, [
        0,
        toBytes32("USDC"),
        6,
        true,
        usdc.address,
        muxUsdc.address,
      ])
    )
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setParams(
      AdminParamsType.SetAssetParams,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetParams, [
        0,
        rate("0"),
        rate("0"),
        rate("0"),
        rate("0"),
        0,
        toWei("0"),
        toWei("0"),
        1,
        "0x0000000000000000000000000000000000000000",
        0,
      ])
    )
    // id, tradable, openable, shortable, useStable
    await pool.setParams(
      AdminParamsType.SetAssetFlags,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetFlags, [0, false, false, false, false])
    )
    await pool.setParams(
      AdminParamsType.SetFundingParams,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetFundingParams, [0, rate("0.0001"), rate("0.0008")])
    )

    // id, symbol, decimals, stable, token, pool
    await pool.setParams(
      AdminParamsType.AddAsset,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.AddAsset, [
        1,
        toBytes32("ETH"),
        18,
        false,
        weth.address,
        muxWeth.address,
      ])
    )
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setParams(
      AdminParamsType.SetAssetParams,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetParams, [
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
        0,
      ])
    )
    // id, tradable, openable, shortable, useStable
    await pool.setParams(
      AdminParamsType.SetAssetFlags,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetFlags, [1, true, true, true, false])
    )
    await pool.setParams(
      AdminParamsType.SetFundingParams,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetFundingParams, [1, rate("0.0002"), rate("0.0009")])
    )

    await pool.setBlockTimestamp(86400 * 1)
    await pool.setParams(
      AdminParamsType.SetFundingInterval,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetFundingInterval, [3600 * 8])
    )

    await pool.connect(broker).updateFundingState([0, 1], [rate("0.0002"), rate("0.0003")])
    await pool.setBlockTimestamp(86400 * 2)
    await pool.connect(broker).updateFundingState([0, 1], [rate("0.0002"), rate("0.0003")])
  })

  it("+liq usdc, -liq usdc, short eth using usdc, close, long eth using weth, close", async () => {
    // +liq usdc
    await usdc.connect(lp1).approve(orderBook.address, toUnit("1000000", 6))
    {
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(0, toUnit("1000000", 6), true)
      const receipt1 = await tx1.wait()
      console.log("GAS +liq  order", receipt1.gasUsed.toString())
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
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1"), toWei("1000"))
      const receipt1 = await tx1.wait()
      console.log("GAS +liq  fill ", receipt1.gasUsed.toString())
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000000", 6))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("1000"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999000"))
    }
    // -liq usdc
    await mlp.connect(lp1).approve(orderBook.address, toWei("1"))
    {
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(0, toWei("1"), false)
      const receipt1 = await tx1.wait()
      console.log("GAS -liq  order", receipt1.gasUsed.toString())
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 1, 0, toWei("1"), false)
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("1"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999000"))
    }
    {
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(1, toWei("1"), toWei("2000"))
      const receipt1 = await tx1.wait()
      console.log("GAS -liq  fill ", receipt1.gasUsed.toString())
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("2000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("998000", 6))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999001"))
    }
    // short eth using usdc
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      const tx1 = await orderBook
        .connect(trader1)
        .placePositionOrder(
          shortAccountId,
          toUnit("1000", 6),
          toWei("1"),
          toWei("1000"),
          0,
          PositionOrderFlags.OpenPosition
        )
      const receipt1 = await tx1.wait()
      console.log("GAS short order", receipt1.gasUsed.toString())
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(shortAccountId, 2, toUnit("1000", 6), toWei("1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
    }
    {
      const tx1 = await orderBook.connect(broker).fillPositionOrder(2, toWei("1"), toWei("2000"))
      const receipt1 = await tx1.wait()
      console.log("GAS short fill ", receipt1.gasUsed.toString())
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999000", 6))
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2000 * 1 * 0.001 = 2
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0006"))
      // TODO: collected fee
    }
    // long eth using weth
    const longAccountId = assembleSubAccountId(trader1.address, 1, 1, true)
    await weth.connect(trader1).approve(orderBook.address, toWei("100"))
    {
      const tx1 = await orderBook
        .connect(trader1)
        .placePositionOrder(longAccountId, toWei("100"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition)
      const receipt1 = await tx1.wait()
      console.log("GAS long  order", receipt1.gasUsed.toString())
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 3, toWei("100"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition)
      expect(await weth.balanceOf(trader1.address)).to.equal(toWei("0"))
      expect(await weth.balanceOf(orderBook.address)).to.equal(toWei("100"))
    }
    {
      const tx1 = await orderBook.connect(broker).fillPositionOrder(3, toWei("2000"), toWei("2000"))
      const receipt1 = await tx1.wait()
      console.log("GAS long  fill ", receipt1.gasUsed.toString())
      expect(await weth.balanceOf(trader1.address)).to.equal(toWei("0"))
      expect(await weth.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth.balanceOf(pool.address)).to.equal(toWei("100"))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("99.999")) // fee = 1 * 0.001 = 0.001
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
      // TODO: collected fee
    }
    // close short, profit in usdc
    // close long, profit in muxEth
  })
})
