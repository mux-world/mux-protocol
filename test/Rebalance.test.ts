import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { BigNumber, Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, rate, PreMinedTokenTotalSupply, createFactory } from "./deployUtils"
import { createContract } from "./deployUtils"
import { MlpToken, TestOrderBook, TestLiquidityPool, LiquidityManager, MockERC20, Reader, TestRebalancer } from "../typechain"
const U = ethers.utils

describe("Rebalance", () => {
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let orderBook: TestOrderBook
  let liquidityManager: LiquidityManager
  let usdc: Contract
  let weth9: MockERC20
  let muxUsd: Contract
  let muxWeth: Contract
  let nativeUnwrapper: Contract
  let rebalancer: TestRebalancer

  let lp1: SignerWithAddress
  let broker: SignerWithAddress
  let vault: SignerWithAddress

  before(async () => {
    const accounts = await ethers.getSigners()
    lp1 = accounts[1]
    broker = accounts[2]
    vault = accounts[3]
  })

  beforeEach(async () => {
    const poolHop1 = await createContract("TestLiquidityPoolHop1")
    const poolHop2 = await createContract("TestLiquidityPoolHop2")
    pool = (await createFactory("TestLiquidityPool")).attach(poolHop1.address)
    mlp = (await createContract("MlpToken")) as MlpToken
    orderBook = (await createContract("TestOrderBook")) as TestOrderBook
    liquidityManager = (await createContract("LiquidityManager")) as LiquidityManager
    weth9 = (await createContract("WETH9")) as MockERC20
    nativeUnwrapper = await createContract("NativeUnwrapper", [weth9.address])
    rebalancer = (await createContract("TestRebalancer", [pool.address, orderBook.address])) as TestRebalancer
    await mlp.initialize("MLP", "MLP")
    await orderBook.initialize(pool.address, mlp.address, weth9.address, nativeUnwrapper.address)
    await orderBook.addBroker(broker.address)
    await liquidityManager.initialize(vault.address, pool.address)
    await pool.initialize(poolHop2.address, mlp.address, orderBook.address, liquidityManager.address, weth9.address, nativeUnwrapper.address, vault.address)
    // fundingInterval, mlpPrice, mlpPrice, liqBase, liqDyn, σ_strict, brokerGas
    await pool.setNumbers(3600 * 8, toWei("1"), toWei("2000"), rate("0.0001"), rate("0.0000"), rate("0.01"), toWei("0"))
    await nativeUnwrapper.addWhiteList(pool.address)
    await nativeUnwrapper.addWhiteList(orderBook.address)
    await mlp.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    usdc = await createContract("MockERC20", ["Usdc", "Usdc", 6])

    muxUsd = await createContract("MuxToken")
    await muxUsd.initialize("muxUsd", "muxUsd")
    await muxUsd.transfer(pool.address, toWei(PreMinedTokenTotalSupply))
    muxWeth = await createContract("MuxToken")
    await muxWeth.initialize("muxWeth", "muxWeth")
    await muxWeth.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    // 0 = dummy
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("DUMMY"), 18, false, "0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000")

    // 1 = ETH
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(1, toBytes32("ETH"), 18, false, weth9.address, muxWeth.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, spread
    await pool.setAssetParams(1, rate("0.1"), rate("0.05"), rate("0.001"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2, rate("0"))
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(1, true, true, true, false, true, false)
    await pool.setFundingParams(1, rate("0.0003"), rate("0.0009"))

    // 2 = USDC
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(2, toBytes32("USDC"), 6, true, usdc.address, muxUsd.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, spread
    await pool.setAssetParams(2, rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1, rate("0"))
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(2, false, false, false, false, true, true)
    await pool.setFundingParams(2, rate("0.0002"), rate("0.0008"))

    await pool.setBlockTimestamp(86400 * 1)
    await orderBook.setBlockTimestamp(86400 * 1)
    await orderBook.connect(broker).updateFundingState(rate("0"), [0, 1], [rate("0"), rate("0")], [toWei("1"), toWei("3000")])
    await pool.setBlockTimestamp(86400 * 2)
    await orderBook.setBlockTimestamp(86400 * 2)
    await orderBook.connect(broker).updateFundingState(rate("0"), [0, 1], [rate("0"), rate("0")], [toWei("1"), toWei("3000")])
    await orderBook.addRebalancer(rebalancer.address)

    // add liq
    const current = toWei("29700")
    const target = toWei("29700")
    // +liq eth
    {
      await expect(orderBook.connect(lp1).placeLiquidityOrder(1, toWei("100"), true, { value: toWei("100") }))
        .to.emit(orderBook, "NewLiquidityOrder")
        .withArgs(lp1.address, 0, 1, toWei("100"), true)
    }
    {
      await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1000"), toWei("1000"), current, target)
      const tokenInfo0 = await pool.getAssetInfo(1)
      expect(tokenInfo0.spotLiquidity).to.equal(toWei("100")) // fee = 0.01
      expect(tokenInfo0.collectedFee).to.equal(toWei("0.01"))
    }
  })

  it("good", async () => {
    await usdc.mint(rebalancer.address, toUnit("300000", 6))
    {
      await expect(
        orderBook
          .connect(lp1)
          .placeRebalanceOrder(1, 2, toWei("100"), toUnit("99999999", 6), "0xe0e5df977c8fd4547a156835a1328d03794e4b169d7d6d318bcbe2516bd8265b")
      ).to.revertedWith("BAL")
      await expect(rebalancer.placeOrder(1, 2, toWei("100"), toUnit("99999999", 6)))
        .to.emit(orderBook, "NewRebalanceOrder")
        .withArgs(rebalancer.address, 1, 1, 2, toWei("100"), toUnit("99999999", 6), "0xe0e5df977c8fd4547a156835a1328d03794e4b169d7d6d318bcbe2516bd8265b")
    }
    {
      await expect(orderBook.fillRebalanceOrder(1, toWei("3000"), toWei("1"))).to.revertedWith("BKR")
      await orderBook.connect(broker).fillRebalanceOrder(1, toWei("3000"), toWei("1"))
      expect(await usdc.balanceOf(rebalancer.address)).to.equal(toUnit("30", 6)) //  // 100 * 3000  / 1 * 0.0001
      const tokenInfo0 = await pool.getAssetInfo(1)
      expect(tokenInfo0.spotLiquidity).to.equal(toWei("0"))
      expect(tokenInfo0.collectedFee).to.equal(toWei("0.01"))
      const tokenInfo1 = await pool.getAssetInfo(2)
      expect(tokenInfo1.spotLiquidity).to.equal(toWei("299970")) //  // 100 * 3000  / 1 * 0.9999
      expect(tokenInfo1.collectedFee).to.equal(toWei("0"))
    }
  })

  it("limit by price", async () => {
    await usdc.mint(rebalancer.address, toUnit("300000", 6))
    await rebalancer.placeOrder(1, 2, toWei("100"), toUnit("299969.9", 6))
    await expect(orderBook.connect(broker).fillRebalanceOrder(1, toWei("3000"), toWei("1"))).to.revertedWith("LMT")
  })
})
