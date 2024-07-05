import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { BigNumber, Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, rate, PreMinedTokenTotalSupply, createFactory } from "./deployUtils"
import { createContract, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { MlpToken, TestOrderBook, TestLiquidityPool, LiquidityManager, MockERC20, Reader } from "../typechain"
const U = ethers.utils

describe("IntegrationEth", () => {
  const refCode = toBytes32("")
  const posExtra = {
    tpPrice: "0",
    slPrice: "0",
    tpslProfitTokenId: 0,
    tpslDeadline: 0,
  }
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let orderBook: TestOrderBook
  let liquidityManager: LiquidityManager
  let weth9: MockERC20
  let muxWeth: Contract
  let reader: Reader
  let nativeUnwrapper: Contract

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
    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("TestOrderBook", [], { "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook })) as TestOrderBook
    liquidityManager = (await createContract("LiquidityManager")) as LiquidityManager
    weth9 = (await createContract("WETH9")) as MockERC20
    nativeUnwrapper = await createContract("NativeUnwrapper", [weth9.address])
    reader = (await createContract("Reader", [pool.address, mlp.address, liquidityManager.address, orderBook.address, []])) as Reader
    await mlp.initialize("MLP", "MLP")
    await orderBook.initialize(pool.address, mlp.address, weth9.address, nativeUnwrapper.address)
    await orderBook.addBroker(broker.address)
    await orderBook.setLiquidityLockPeriod(5 * 60)
    await orderBook.setOrderTimeout(300, 86400 * 365, 5) // marketOrder, limitOrder, cancel
    await liquidityManager.initialize(vault.address, pool.address)
    await pool.initialize(poolHop2.address, mlp.address, orderBook.address, weth9.address, nativeUnwrapper.address, vault.address)
    // fundingInterval, liqBase, liqDyn, σ_strict, brokerGas
    await pool.setNumbers(3600 * 8, rate("0.0001"), rate("0.0000"), rate("0.01"), toWei("0"))
    // mlpPrice, mlpPrice
    await pool.setEmergencyNumbers(toWei("1"), toWei("2000"))
    await pool.setLiquidityManager(liquidityManager.address, true)
    await nativeUnwrapper.addWhiteList(pool.address)
    await nativeUnwrapper.addWhiteList(orderBook.address)
    await mlp.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    muxWeth = await createContract("MuxToken")
    await muxWeth.initialize("muxWeth", "muxWeth")
    await muxWeth.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    // 0 = ETH
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("ETH"), 18, false, weth9.address, muxWeth.address)
    // id, symbol, imr, mmr, fee, fee, minBps, minTime, spotWeight
    await pool.setAssetParams(0, toBytes32("ETH"), rate("0.1"), rate("0.05"), rate("0.001"), rate("0.001"), rate("0.01"), 10, 2)
    // id, tradable, openable, shortable, useStable, enabled, strict, liq, halfSpread, maxLong, maxShort
    await pool.setAssetFlags(0, true, true, true, false, true, false, true, rate("0"), toWei("10000000"), toWei("10000000"))
    await pool.setFundingParams(0, rate("0.0003"), rate("0.0009"))

    await pool.setBlockTimestamp(86400 * 1)
    await orderBook.setBlockTimestamp(86400 * 1)
    await orderBook.connect(broker).updateFundingState(rate("0"), [0], [rate("0")], [toWei("3000")])
    await pool.setBlockTimestamp(86400 * 2)
    await orderBook.setBlockTimestamp(86400 * 2)
    await orderBook.connect(broker).updateFundingState(rate("0"), [0], [rate("0")], [toWei("3000")])
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
      await expect(pool.connect(trader1).withdrawAllCollateral(longAccountId)).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).withdrawAllCollateral(longAccountId)).to.revertedWith("SND")
      await orderBook.connect(trader1).withdrawAllCollateral(longAccountId)
      expect(await ethers.provider.getBalance(orderBook.address)).to.equal(toWei("0"))
      expect(await ethers.provider.getBalance(pool.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(trader1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("0"))
    }
  })

  it("cancel order will return ETH", async () => {
    // +liq eth
    {
      const balance1 = await ethers.provider.getBalance(lp1.address)
      await pool.setBlockTimestamp(86400 * 2 + 0)
      await orderBook.setBlockTimestamp(86400 * 2 + 0)
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(0, toWei("100"), true, { value: toWei("100") })
      const receipt1 = await tx1.wait()
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 0, 0, toWei("100"), true)
      const balance2 = await ethers.provider.getBalance(lp1.address)
      expect(balance1.sub(balance2).gte(toWei("100"))).to.true
      expect(balance1.sub(balance2).lt(toWei("100.01"))).to.true
      await expect(orderBook.connect(lp1).cancelOrder(0)).to.revertedWith("CLD")
      await pool.setBlockTimestamp(86400 * 2 + 5)
      await orderBook.setBlockTimestamp(86400 * 2 + 5)
      await orderBook.connect(lp1).cancelOrder(0)
      const balance3 = await ethers.provider.getBalance(lp1.address)
      expect(balance1.sub(balance3).lt(toWei("0.01"))).to.true
    }
  })

  it("+/-liquidity, +/-trade", async () => {
    const current = toWei("29700")
    const target = toWei("29700")
    // +liq eth
    {
      await pool.setBlockTimestamp(86400 * 2 + 0)
      await orderBook.setBlockTimestamp(86400 * 2 + 0)
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(0, toWei("100"), true, { value: toWei("100") })
      const receipt1 = await tx1.wait()
      console.log("GAS +liq order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 0, 0, toWei("100"), true)
      expect(await weth9.balanceOf(lp1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("100"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))
      const readerState = await reader.callStatic.getChainStorage()
      expect(readerState.lpDeduct).to.eq(toWei("1000000000000000000"))
    }
    {
      await expect(orderBook.connect(broker).fillLiquidityOrder(0, toWei("1000"), toWei("1000"), current, target)).to.revertedWith("LCK")
      await pool.setBlockTimestamp(86400 * 2 + 330)
      await orderBook.setBlockTimestamp(86400 * 2 + 330)
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1000"), toWei("1000"), current, target)
      const receipt1 = await tx1.wait()
      console.log("GAS +liq fill ", receipt1.gasUsed.toString(), tx1.hash)
      expect(await weth9.balanceOf(lp1.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("99.99")) // (100 - fee) * 1000 / 1000
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999900.01"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("100")) // fee = 0.01
      expect(collateralInfo.collectedFee).to.equal(toWei("0.01"))
      const readerState = await reader.callStatic.getChainStorage()
      expect(readerState.lpDeduct).to.eq(toWei("999999999999999900.01"))
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
      const readerState = await reader.callStatic.getChainStorage()
      expect(readerState.lpDeduct).to.eq(toWei("999999999999999900.01"))
    }
    {
      const balance1 = await ethers.provider.getBalance(lp1.address)
      await expect(orderBook.connect(broker).fillLiquidityOrder(1, toWei("1000"), toWei("2000"), current, target)).to.revertedWith("LCK")
      await pool.setBlockTimestamp(86400 * 2 + 660)
      await orderBook.setBlockTimestamp(86400 * 2 + 660)
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(1, toWei("1000"), toWei("2000"), current, target)
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
      const readerState = await reader.callStatic.getChainStorage()
      expect(readerState.lpDeduct).to.eq(toWei("999999999999999901.01"))
    }
    // open long eth, using eth
    const longAccountId = assembleSubAccountId(trader1.address, 0, 0, true)
    {
      const tx1 = await orderBook
        .connect(trader1)
        .placePositionOrder3(longAccountId, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode, posExtra, { value: toWei("0.5") })
      const receipt1 = await tx1.wait()
      console.log("GAS +lng order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 2, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100)
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
      const tx1 = await orderBook.connect(trader1).placePositionOrder3(longAccountId, toWei("0"), toWei("1"), toWei("1000"), 0, PositionOrderFlags.WithdrawAllIfEmpty, 86400 * 100, refCode, posExtra)
      const receipt1 = await tx1.wait()
      console.log("GAS -lng order", receipt1.gasUsed.toString(), tx1.hash)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(longAccountId, 3, toWei("0"), toWei("1"), toWei("1000"), 0, PositionOrderFlags.WithdrawAllIfEmpty, 86400 * 100)
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
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
    // broker claim gas rebate
    {
      // fundingInterval, liqBase, liqDyn, σ_strict, brokerGas
      await pool.setNumbers(3600 * 8, rate("0.0001"), rate("0.0000"), rate("0.01"), toWei("0.0001"))
      expect(await orderBook.connect(broker).callStatic.claimBrokerGasRebate()).to.equal(toWei("0.0004"))
      const balance1 = await ethers.provider.getBalance(broker.address)
      const tx1 = await orderBook.connect(broker).claimBrokerGasRebate()
      const receipt1 = await tx1.wait()
      const balance2 = await ethers.provider.getBalance(broker.address) // fee = 0
      const actual = balance2.sub(balance1).add(receipt1.gasUsed.mul(tx1.gasPrice!))
      expect(actual).eq(toWei("0.0004"))
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("97.954180952380952381")) // -= 0.0004
      expect(assetInfo.collectedFee).to.equal(toWei("0.0122")) // unchanged
    }
  })

  it("withdraw", async () => {
    const current = toWei("29700")
    const target = toWei("29700")
    // +liq eth
    {
      await pool.setBlockTimestamp(86400 * 2 + 0)
      await orderBook.setBlockTimestamp(86400 * 2 + 0)
      await orderBook.connect(lp1).placeLiquidityOrder(0, toWei("100"), true, { value: toWei("100") })
      await pool.setBlockTimestamp(86400 * 2 + 330)
      await orderBook.setBlockTimestamp(86400 * 2 + 330)
      await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1000"), toWei("1000"), current, target)
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("100"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.01"))
    }
    // open long eth, using eth
    const longAccountId = assembleSubAccountId(trader1.address, 0, 0, true)
    {
      await orderBook
        .connect(trader1)
        .placePositionOrder3(longAccountId, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode, posExtra, { value: toWei("0.5") })
      await orderBook.connect(broker).fillPositionOrder(1, toWei("2000"), toWei("2000"), toWei("0"))
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("0.499")) // fee = 0.001
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
      expect(assetInfo.spotLiquidity).to.equal(toWei("100.001"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.011"))
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
      // +liq eth
      {
        await orderBook.connect(lp1).placeLiquidityOrder(0, toWei("100"), true, { value: toWei("100") })
        await pool.setBlockTimestamp(86400 * 2 + 990)
        await orderBook.setBlockTimestamp(86400 * 2 + 990)
        await orderBook.connect(broker).fillLiquidityOrder(0, toWei("2000"), toWei("1"), current, target)
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("100")) // fee = 0.01
        expect(collateralInfo.collectedFee).to.equal(toWei("0.01"))
      }
      // withdraw 100 eth from LiquidityPool to LiquidityManager
      {
        await liquidityManager.addDexSpotConfiguration(1, 0, 100, [0], [1])
        const testPlugin = await createContract("TestPlugin")
        await liquidityManager.setPlugin(testPlugin.address, true)
        const tmp = await ethers.getContractAt("TestPlugin", liquidityManager.address)
        await tmp.pullAssets([0], [toWei("100")])

        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("0"))
        expect(collateralInfo.collectedFee).to.equal(toWei("0.01"))
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.assets[0].deduct).to.eq(toWei("1000000000000000000")) // muxETH supply = 0
        expect(readerState.lpDeduct).to.eq(toWei("999999999999800020")) // lp supply = 199980
      }
    })

    it("close long, profit in muxEth, and redeem muxEth", async () => {
      // open long
      const longAccountId = assembleSubAccountId(trader1.address, 0, 0, true)
      {
        await orderBook
          .connect(trader1)
          .placePositionOrder3(longAccountId, toWei("0.5"), toWei("1"), toWei("3000"), 0, PositionOrderFlags.OpenPosition, 86400 * 100, refCode, posExtra, { value: toWei("0.5") })
        await orderBook.connect(broker).fillPositionOrder(1, toWei("2000"), toWei("2000"), toWei("0"))
        expect(await weth9.balanceOf(pool.address)).to.equal(toWei("0.5"))
        const subAccount = await pool.getSubAccount(longAccountId)
        expect(subAccount.collateral).to.equal(toWei("0.499")) // fee = 0.001
        expect(subAccount.size).to.equal(toWei("1"))
        expect(subAccount.entryPrice).to.equal(toWei("2000"))
        expect(subAccount.entryFunding).to.equal(toWei("0.0009"))
        const assetInfo = await pool.getAssetInfo(0)
        expect(assetInfo.spotLiquidity).to.equal(toWei("0.001"))
        expect(assetInfo.collectedFee).to.equal(toWei("0.011"))
        expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
        expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
        expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
        expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
      }
      // close long, profit in muxBtc, auto withdraw all
      {
        await orderBook.connect(trader1).placePositionOrder3(longAccountId, toWei("0"), toWei("1"), toWei("1000"), 0, PositionOrderFlags.WithdrawAllIfEmpty, 86400 * 100, refCode, posExtra)
        const balance1 = await ethers.provider.getBalance(trader1.address)
        await orderBook.connect(broker).fillPositionOrder(2, toWei("2100"), toWei("2100"), toWei("2100")) // pnl = 100
        const balance2 = await ethers.provider.getBalance(trader1.address)
        expect(balance2.sub(balance1).lte(toWei("0.5"))).to.true // collateral + [0].spotLiquidity
        expect(balance2.sub(balance1).gt(toWei("0.0009"))).to.true
        expect(await muxWeth.balanceOf(trader1.address)).to.equal(toWei("0.045619047619047619")) // += pnl / mark - fee - [0].spotLiquidity
        const subAccount = await pool.getSubAccount(longAccountId)
        expect(subAccount.collateral).to.equal(toWei("0"))
        expect(subAccount.size).to.equal(toWei("0"))
        expect(subAccount.entryPrice).to.equal(toWei("0"))
        expect(subAccount.entryFunding).to.equal(toWei("0"))
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("0"))
        expect(collateralInfo.collectedFee).to.equal(toWei("0.012"))
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999800020")) // lp supply = 199980
        expect(readerState.assets[0].deduct).to.eq(toWei("999999999999999999.954380952380952381")) // muxETH supply = 0.045619047619047619
      }
      // deposit 1 wbtc from LiquidityManager to LiquidityPool
      {
        const tmp = await ethers.getContractAt("TestPlugin", liquidityManager.address)
        await tmp.pushAssets([0], [toWei("1")])
        expect(await weth9.balanceOf(pool.address)).to.equal(toWei("1"))
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("1"))
        expect(collateralInfo.collectedFee).to.equal(toWei("0.012"))
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999800020")) // lp supply = 199980
        expect(readerState.assets[0].deduct).to.eq(toWei("999999999999999999.954380952380952381")) // muxETH supply = 0.045619047619047619
      }
      // redeem muxBtc
      await muxWeth.connect(trader1).approve(orderBook.address, toWei("0.045619047619047619"))
      {
        const balance1 = await ethers.provider.getBalance(trader1.address)
        await orderBook.connect(trader1).redeemMuxToken(0, toWei("0.045619047619047619"))
        const balance2 = await ethers.provider.getBalance(trader1.address)
        expect(balance2.sub(balance1).lte(toWei("0.045619047619047619"))).to.true
        expect(balance2.sub(balance1).gt(toWei("0.0454"))).to.true
        const collateralInfo = await pool.getAssetInfo(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("0.954380952380952381"))
        expect(collateralInfo.collectedFee).to.equal(toWei("0.012"))
        const readerState = await reader.callStatic.getChainStorage()
        expect(readerState.lpDeduct).to.eq(toWei("999999999999800020")) // lp supply = 199980
        expect(readerState.assets[0].deduct).to.eq(toWei("1000000000000000000")) // muxETH supply = 0
      }
    })
  })
})
