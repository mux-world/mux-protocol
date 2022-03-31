import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import {
  toWei,
  createContract,
  toBytes32,
  rate,
  assembleSubAccountId,
  PreMinedTokenTotalSupply,
  createFactory,
  toChainlink,
  ReferenceOracleType,
} from "./deployUtils"
import { TestLiquidityPool } from "../typechain"
import { MockChainlink, TestMlpTimeLock } from "../typechain"
const U = ethers.utils

describe("Trade", () => {
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  let mlp: Contract
  let pool: TestLiquidityPool
  let mlpTimeLock: TestMlpTimeLock
  let asset0: Contract
  let asset1: Contract
  let asset2: Contract
  let muxAsset0: Contract
  let muxAsset1: Contract
  let muxAsset2: Contract

  let user0: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let user3: SignerWithAddress

  before(async () => {
    const accounts = await ethers.getSigners()
    user0 = accounts[0]
    user1 = accounts[1]
    user2 = accounts[2]
    user3 = accounts[3]
  })

  beforeEach(async () => {
    const poolHop1 = await createContract("TestLiquidityPoolHop1", [])
    const poolHop2 = await createContract("TestLiquidityPoolHop2", [])
    pool = (await createFactory("TestLiquidityPool")).attach(poolHop1.address)
    mlp = await createContract("MockERC20", ["MLP", "MLP", 18])
    mlpTimeLock = (await createContract("TestMlpTimeLock")) as TestMlpTimeLock
    await mlp.mint(pool.address, toWei(PreMinedTokenTotalSupply))
    await pool.initialize(poolHop2.address, mlp.address, user0.address /* test only */, user0.address /* test only */, weth9, mlpTimeLock.address)
    // fundingInterval, mlpPrice, mlpPrice
    await pool.setNumbers(3600 * 8, toWei("1"), toWei("2"))
    await mlpTimeLock.initialize(mlp.address, pool.address)

    asset0 = await createContract("MockERC20", ["AST0", "AST0", 18])
    asset1 = await createContract("MockERC20", ["AST1", "AST1", 18])
    asset2 = await createContract("MockERC20", ["AST2", "AST2", 18])
    muxAsset0 = await createContract("MockERC20", ["MUX0", "MUX0", 18])
    muxAsset1 = await createContract("MockERC20", ["MUX1", "MUX1", 18])
    muxAsset2 = await createContract("MockERC20", ["MUX2", "MUX2", 18])
    await muxAsset0.mint(pool.address, toWei(PreMinedTokenTotalSupply))
    await muxAsset1.mint(pool.address, toWei(PreMinedTokenTotalSupply))
    await muxAsset2.mint(pool.address, toWei(PreMinedTokenTotalSupply))

    // Asset 0 - stable
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("AST0"), 18, true, asset0.address, muxAsset0.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(0, rate("0.1"), rate("0.05"), rate("0.01"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 1)
    // id, tradable, openable, shortable, useStable
    await pool.setAssetFlags(0, true, true, true, false)
    await pool.setFundingParams(0, rate("0.0003"), rate("0.0009"))

    // Asset 1 - position
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(1, toBytes32("AST1"), 18, false, asset1.address, muxAsset1.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(1, rate("0.1"), rate("0.05"), rate("0.01"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2)
    // id, tradable, openable, shortable, useStable
    await pool.setAssetFlags(1, true, true, true, false)
    await pool.setFundingParams(1, rate("0.0002"), rate("0.0008"))

    // Asset 2 - another stable
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(2, toBytes32("AST2"), 18, true, asset2.address, muxAsset2.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(2, rate("0.1"), rate("0.05"), rate("0.01"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 1)
    // id, tradable, openable, shortable, useStable
    await pool.setAssetFlags(2, true, true, true, false)
    await pool.setFundingParams(2, rate("0.0003"), rate("0.0009"))

    // Asset 3 - another position, useStable = true
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(3, toBytes32("AST3"), 18, false, "0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000")
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(3, rate("0.1"), rate("0.05"), rate("0.01"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2)
    // id, tradable, openable, shortable, useStable
    await pool.setAssetFlags(3, true, true, true, true)
    await pool.setFundingParams(3, rate("0.0002"), rate("0.0008"))
  })

  it("addLiquidity", async () => {
    const feeRate1 = rate("0")
    await asset0.mint(user0.address, toWei("10000"))
    expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))

    // user 0 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await expect(pool.addLiquidity(user0.address, 0, toWei("1"), toWei("0.1"), feeRate1)).to.revertedWith("MPO")
      await expect(pool.addLiquidity(user0.address, 0, toWei("1"), toWei("2.1"), feeRate1)).to.revertedWith("MPO")
      await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("100"))
      await mlpTimeLock.connect(user0).claimMlp()
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999900"))
    }
    // user 0 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("2"), feeRate1) // = 50 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("200"))
      await mlpTimeLock.connect(user0).claimMlp()
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("150"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999850"))
    }
    // user 1 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user1.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("300"))
      await mlpTimeLock.connect(user1).claimMlp()
      expect(await mlp.balanceOf(user1.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999750"))
    }
    // user 1 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user1.address, 0, toWei("2"), toWei("1"), feeRate1) // = 200 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("400"))
      await mlpTimeLock.connect(user1).claimMlp()
      expect(await mlp.balanceOf(user1.address)).to.equal(toWei("300"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999550"))
    }
  })

  it("removeLiquidity", async () => {
    const feeRate1 = rate("0")

    // add liq
    await asset0.mint(pool.address, toWei("1000"))
    await asset1.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
    await pool.addLiquidity(user1.address, 1, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("1000"))

    // remove liq
    await pool.removeLiquidity(user0.address, toWei("1"), 0, toWei("1"), toWei("1"), feeRate1)
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("1"))
    await pool.removeLiquidity(user0.address, toWei("100"), 0, toWei("2"), toWei("1"), feeRate1)
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("51"))
    await pool.removeLiquidity(user0.address, toWei("200"), 1, toWei("100"), toWei("1"), feeRate1)
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("51"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("2"))
  })

  it("depositCollateral / withdrawCollateral", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)

    await asset0.mint(pool.address, toWei("100"))
    await pool.depositCollateral(subAccountId)
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("100"))

    await asset0.mint(pool.address, toWei("200"))
    await pool.depositCollateral(subAccountId)
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("300"))

    await pool.withdrawCollateral(subAccountId, toWei("50"), toWei("1"), toWei("1"))
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("50"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("250"))
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("250"))
  })

  it("long/short stable coin. should fail", async () => {
    await expect(pool.openPosition(assembleSubAccountId(user0.address, 1, 0, true), toWei("1"), toWei("1"), toWei("100"))).to.revertedWith("Stb")
    await expect(pool.openPosition(assembleSubAccountId(user0.address, 1, 0, false), toWei("1"), toWei("1"), toWei("100"))).to.revertedWith("Stb")
  })

  it("open long, close long, take profit. profit = asset", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
    const subAccountId2 = assembleSubAccountId(user1.address, 0, 1, true)
    const feeRate1 = rate("0")

    // lp = user1
    await asset0.mint(pool.address, toWei("1000"))
    await asset1.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
    await pool.addLiquidity(user1.address, 1, toWei("100"), toWei("1"), feeRate1) // = 100 mlp

    // trader = user0, fee = 1
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId)
    await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
    {
      let subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("100"))
    }

    // trader = user1, fee = 0.5
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId2)
    await pool.openPosition(subAccountId2, toWei("1"), toWei("1"), toWei("50"))
    {
      let subAccount = await pool.getSubAccount(subAccountId2)
      expect(subAccount.collateral).to.equal(toWei("10.5"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("50"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalLongPosition).to.equal(toWei("2"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("75"))
    }

    // user0 100 => 200
    await pool.closePosition(subAccountId, toWei("1"), 1, toWei("1"), toWei("200"), toWei("200"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0.49")) // fee = 2, ((200 - 100) * 1 - fee) / 200
    {
      let subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("50"))
    }

    // user1 50 => 50
    await pool.closePosition(subAccountId2, toWei("1"), 1, toWei("1"), toWei("50"), toWei("50"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0.49")) // fee = 0.5
    {
      let subAccount = await pool.getSubAccount(subAccountId2)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
  })

  it("open short, close short, take profit. profit = another stable", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, false)
    const subAccountId2 = assembleSubAccountId(user1.address, 0, 1, false)
    const feeRate1 = rate("0")

    // lp = user1
    await asset2.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 2, toWei("1"), toWei("1"), feeRate1) // = 100 mlp

    // trader = user0, fee = 1
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId)
    await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
    {
      let subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("100"))
    }

    // trader = user1, fee = 0.5
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId2)
    await pool.openPosition(subAccountId2, toWei("1"), toWei("1"), toWei("50"))
    {
      let subAccount = await pool.getSubAccount(subAccountId2)
      expect(subAccount.collateral).to.equal(toWei("10.5"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("50"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("2"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("75"))
    }

    // user0 100 => 50
    await expect(pool.closePosition(subAccountId, toWei("1"), 1, toWei("1"), toWei("50"), toWei("50"))).to.revertedWith("Stb")
    await pool.closePosition(subAccountId, toWei("1"), 2, toWei("1"), toWei("50"), toWei("1"))
    expect(await asset2.balanceOf(user0.address)).to.equal(toWei("49.5")) // fee = 0.5, ((100 - 50) * 1 - fee)
    {
      let subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("50"))
    }

    // user0 50 => 50
    await pool.closePosition(subAccountId2, toWei("1"), 2, toWei("1"), toWei("50"), toWei("1"))
    {
      let subAccount = await pool.getSubAccount(subAccountId2)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
    }
  })

  it("open long where useStable == true, close long, take profit. profit = stable", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 3, true)
    const feeRate1 = rate("0")

    // lp = user1
    await asset2.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 2, toWei("1"), toWei("1"), feeRate1) // = 100 mlp

    // trader = user0
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId)
    // fee = 100 * 1% = 1
    await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))

    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("10"))
    expect(subAccount.size).to.equal(toWei("1"))
    expect(subAccount.entryPrice).to.equal(toWei("100"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))

    // 100 => 200
    await expect(pool.closePosition(subAccountId, toWei("1"), 1, toWei("1"), toWei("200"), toWei("200"))).to.revertedWith("Stb")
    await pool.closePosition(subAccountId, toWei("1"), 2, toWei("1"), toWei("200"), toWei("1"))
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("10"))
    expect(subAccount.size).to.equal(toWei("0"))
    expect(subAccount.entryPrice).to.equal(toWei("0"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))
    expect(await asset2.balanceOf(user0.address)).to.equal(toWei("98")) // fee = 2, ((200 - 100) * 1 - fee)
  })

  it("liquidate short", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, false)
    const feeRate1 = rate("0")

    // trader = user0
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId)
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("11")) // fee = 0, ((110 - 100) * 1 - fee)

    // fee = 100 * 1% = 1
    await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))

    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("10"))
    expect(subAccount.size).to.equal(toWei("1"))
    expect(subAccount.entryPrice).to.equal(toWei("100"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))
    {
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("1"))
      expect(assetInfo.collectedFee).to.equal(toWei("1"))
    }
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("100"))
    }

    // 100 => 110
    await expect(pool.liquidate(subAccountId, 1, toWei("1"), toWei("100"), toWei("100"))).to.revertedWith("Stb")
    await expect(pool.liquidate(subAccountId, 0, toWei("1"), toWei("100"), toWei("1"))).to.revertedWith("MMS")
    await pool.liquidate(subAccountId, 0, toWei("1"), toWei("110"), toWei("1"))
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("0"))
    expect(subAccount.size).to.equal(toWei("0"))
    expect(subAccount.entryPrice).to.equal(toWei("0"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("11")) // fee = 0, ((110 - 100) * 1 - fee)
    {
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("11"))
      expect(assetInfo.collectedFee).to.equal(toWei("1"))
    }
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
    }
  })

  it("getFundingRate", async () => {
    let funding = await pool.getFundingRatePublic(rate("0.0003"), rate("0.0009"), rate("0"), 8 * 3600)
    expect(funding.newFundingRate).to.equal(rate("0.0003"))
    expect(funding.cumulativeFunding).to.equal(toWei("0.0003"))
    funding = await pool.getFundingRatePublic(rate("0.0003"), rate("0.0009"), rate("0.5"), 8 * 3600)
    expect(funding.newFundingRate).to.equal(rate("0.00045"))
    expect(funding.cumulativeFunding).to.equal(toWei("0.00045"))
    funding = await pool.getFundingRatePublic(rate("0.0003"), rate("0.0009"), rate("1"), 8 * 3600)
    expect(funding.newFundingRate).to.equal(rate("0.0009"))
    expect(funding.cumulativeFunding).to.equal(toWei("0.0009"))
  })

  it("updateFundingState", async () => {
    await pool.setBlockTimestamp(3600 * 8 * 10 + 600) // should truncate
    await pool.updateFundingState(rate("0"), [1, 3], [rate("0"), rate("0")])

    {
      const storage = await pool.getLiquidityPoolStorage()
      expect(storage.u32s[0]).to.eq(rate("0.0003")) // shortFundingBaseRate8H
      expect(storage.u32s[1]).to.eq(rate("0.0009")) // shortFundingLimitRate8H
      expect(storage.u32s[2]).to.eq(3600 * 8 * 10) // lastFundingTime
      expect(storage.u128s[0]).to.eq(toWei("0")) // shortCumulativeFunding
    }
    {
      const assets = await pool.getAllAssetInfo()
      expect(assets[1].longFundingBaseRate8H).to.eq(rate("0.0002"))
      expect(assets[1].longFundingLimitRate8H).to.eq(rate("0.0008"))
      expect(assets[1].longCumulativeFunding).to.eq(toWei("0"))
      expect(assets[3].longFundingBaseRate8H).to.eq(rate("0.0002"))
      expect(assets[3].longFundingLimitRate8H).to.eq(rate("0.0008"))
      expect(assets[3].longCumulativeFunding).to.eq(toWei("0"))
    }
    await pool.setBlockTimestamp(3600 * 8 * 11 + 900) // should truncate
    await pool.updateFundingState(rate("0.5"), [1, 3], [rate("0.5"), rate("1")])
    {
      const storage = await pool.getLiquidityPoolStorage()
      expect(storage.u32s[2]).to.eq(3600 * 8 * 11) // lastFundingTime
      expect(storage.u128s[0]).to.eq(toWei("0.00045")) // shortCumulativeFunding
    }
    {
      const assets = await pool.getAllAssetInfo()
      expect(assets[1].longCumulativeFunding).to.eq(toWei("0.0004"))
      expect(assets[3].longCumulativeFunding).to.eq(toWei("0.0008"))
    }
  })

  describe("muxToken", async () => {
    it("close long, profit in muxBtc, and redeem muxBtc", async () => {
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
      const feeRate1 = rate("0")

      // trader = user0
      await asset0.mint(pool.address, toWei("11"))
      await pool.depositCollateral(subAccountId)

      // fee = 100 * 1% = 1
      await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))

      var subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))

      // 100 => 200
      await pool.closePosition(subAccountId, toWei("1"), 1, toWei("1"), toWei("200"), toWei("200"))
      var subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      expect(await muxAsset1.balanceOf(user0.address)).to.equal(toWei("0.49")) // fee = 2, ((200 - 100) * 1 - fee) / 200
      expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0"))

      // deposit liquidity, lp = user1
      await asset1.mint(pool.address, toWei("1000"))
      await pool.addLiquidity(user1.address, 1, toWei("100"), toWei("1"), feeRate1) // = 100 mlp

      // redeem muxBtc
      await pool.redeemMuxToken(user0.address, 1, toWei("0.49"))
      expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0.49"))
    })
    it("remove liquidity in muxBtc", async () => {
      const feeRate1 = rate("0")

      // remove liq
      await pool.removeLiquidity(user0.address, toWei("1"), 0, toWei("1"), toWei("1"), feeRate1)
      expect(await muxAsset0.balanceOf(user0.address)).to.equal(toWei("1"))
      expect(await asset0.balanceOf(user0.address)).to.equal(toWei("0"))
      expect(await asset2.balanceOf(user0.address)).to.equal(toWei("0"))

      // add liq
      await asset0.mint(pool.address, toWei("1"))
      await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("1"))

      // redeem muxUsd
      await expect(pool.redeemMuxToken(user0.address, 2, toWei("1"))).to.revertedWith("Liq")
      await pool.redeemMuxToken(user0.address, 0, toWei("1"))
      expect(await asset0.balanceOf(user0.address)).to.equal(toWei("1"))
    })
  })

  describe("withdrawProfit", async () => {
    it("open long, withdrawProfit. profit = asset", async () => {
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
      const feeRate1 = rate("0")

      // lp = user1
      await asset0.mint(pool.address, toWei("1000"))
      await asset1.mint(pool.address, toWei("1000"))
      await pool.addLiquidity(user1.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
      await pool.addLiquidity(user1.address, 1, toWei("100"), toWei("1"), feeRate1) // = 100 mlp

      // trader = user0
      await asset0.mint(pool.address, toWei("16"))
      await pool.depositCollateral(subAccountId)

      // fee = 100 * 1% = 1
      await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
      var subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("15"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      {
        let asset = await pool.getAssetInfo(1)
        expect(asset.averageLongPrice).to.equal(toWei("100"))
        expect(asset.totalLongPosition).to.equal(toWei("1"))
      }

      // 100 => 200, fee = 0, pnl = (125 - 100) * 1 / 125 = 0.2
      await expect(pool.withdrawProfit(subAccountId, toWei("0.21"), 1, toWei("1"), toWei("125"), toWei("125"))).to.revertedWith("U<W")
      await expect(pool.withdrawProfit(subAccountId, toWei("0.1"), 1, toWei("1"), toWei("99"), toWei("99"))).to.revertedWith("U<0")
      await pool.withdrawProfit(subAccountId, toWei("0.2"), 1, toWei("1"), toWei("125"), toWei("125"))
      var subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("15"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("125"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0.2"))
      {
        let asset = await pool.getAssetInfo(1)
        expect(asset.averageLongPrice).to.equal(toWei("125"))
        expect(asset.totalLongPosition).to.equal(toWei("1"))
      }
    })

    it("open short, withdrawProfit. profit = another stable", async () => {
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, false)
      const feeRate1 = rate("0")

      // lp = user1
      await asset2.mint(pool.address, toWei("1000"))
      await pool.addLiquidity(user1.address, 2, toWei("1"), toWei("1"), feeRate1) // = 100 mlp

      // trader = user0
      await asset0.mint(pool.address, toWei("11"))
      await pool.depositCollateral(subAccountId)

      // collateral = 11
      await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))

      var subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      {
        let asset = await pool.getAssetInfo(1)
        expect(asset.averageShortPrice).to.equal(toWei("100"))
        expect(asset.totalShortPosition).to.equal(toWei("1"))
      }

      // 100 => 50, fee = 0, pnl = (100 - 50) * 1 = 50
      await expect(pool.withdrawProfit(subAccountId, toWei("50"), 1, toWei("1"), toWei("50"), toWei("50"))).to.revertedWith("Stb")
      await expect(pool.withdrawProfit(subAccountId, toWei("51"), 2, toWei("1"), toWei("50"), toWei("50"))).to.revertedWith("U<W")
      await expect(pool.withdrawProfit(subAccountId, toWei("1"), 2, toWei("1"), toWei("101"), toWei("101"))).to.revertedWith("U<0")
      await pool.withdrawProfit(subAccountId, toWei("50"), 2, toWei("1"), toWei("50"), toWei("1"))
      var subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("50"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      expect(await asset2.balanceOf(user0.address)).to.equal(toWei("50"))
      {
        let asset = await pool.getAssetInfo(1)
        expect(asset.averageShortPrice).to.equal(toWei("50"))
        expect(asset.totalShortPosition).to.equal(toWei("1"))
      }
    })
  })

  describe("referencePrice", async () => {
    let mockChainlink: MockChainlink

    beforeEach(async () => {
      mockChainlink = (await createContract("MockChainlink")) as MockChainlink
      await mockChainlink.setAnswer(toChainlink("100"))
      await pool.setReferenceOracle(1, ReferenceOracleType.Chainlink, mockChainlink.address, rate("0.01"))
    })

    it("normal price", async () => {
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)

      // trader = user0
      await asset0.mint(pool.address, toWei("101"))
      await pool.depositCollateral(subAccountId)
      const tx1 = await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
      await expect(tx1).to.emit(pool, "OpenPosition").withArgs(subAccountId, user0.address, 0, 1, true, toWei("1"), toWei("100"), toWei("100"), toWei("1"))
    })

    it("higher reference price", async () => {
      await mockChainlink.setAnswer(toChainlink("200"))
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)

      // trader = user0
      await asset0.mint(pool.address, toWei("101"))
      await pool.depositCollateral(subAccountId)
      const tx1 = await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
      await expect(tx1).to.emit(pool, "OpenPosition").withArgs(subAccountId, user0.address, 0, 1, true, toWei("1"), toWei("198"), toWei("198"), toWei("1.98"))
    })

    it("lower reference price", async () => {
      await mockChainlink.setAnswer(toChainlink("1"))
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)

      // trader = user0
      await asset0.mint(pool.address, toWei("101"))
      await pool.depositCollateral(subAccountId)
      const tx1 = await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
      await expect(tx1)
        .to.emit(pool, "OpenPosition")
        .withArgs(subAccountId, user0.address, 0, 1, true, toWei("1"), toWei("1.01"), toWei("1.01"), toWei("0.0101"))
    })
  })
})
