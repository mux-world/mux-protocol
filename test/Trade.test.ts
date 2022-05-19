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
import { MockChainlink } from "../typechain"
const U = ethers.utils

describe("Trade", () => {
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  let mlp: Contract
  let pool: TestLiquidityPool
  let asset0: Contract
  let asset1: Contract
  let asset2: Contract
  let muxAsset0: Contract
  let muxAsset1: Contract

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
    await mlp.mint(pool.address, toWei(PreMinedTokenTotalSupply))
    await pool.initialize(poolHop2.address, mlp.address, user0.address /* test only */, user0.address /* test only */, weth9, weth9)
    // fundingInterval, mlpPrice, mlpPrice, liqBase, liqDyn
    await pool.setNumbers(3600 * 8, toWei("1"), toWei("2"), rate("0.000"), rate("0.000"))

    asset0 = await createContract("MockERC20", ["AST0", "AST0", 18])
    asset1 = await createContract("MockERC20", ["AST1", "AST1", 18])
    asset2 = await createContract("MockERC20", ["AST2", "AST2", 18])
    muxAsset0 = await createContract("MockERC20", ["MUX0", "MUX0", 18])
    muxAsset1 = await createContract("MockERC20", ["MUX1", "MUX1", 18])
    await muxAsset0.mint(pool.address, toWei(PreMinedTokenTotalSupply))
    await muxAsset1.mint(pool.address, toWei(PreMinedTokenTotalSupply))

    // Asset 0 - strict stable
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("AST0"), 18, true, asset0.address, muxAsset0.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(0, rate("0.1"), rate("0.05"), rate("0.01"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 1)
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(0, true, true, true, false, true, true)
    await pool.setFundingParams(0, rate("0.0003"), rate("0.0009"))

    // Asset 1 - position
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(1, toBytes32("AST1"), 18, false, asset1.address, muxAsset1.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(1, rate("0.1"), rate("0.05"), rate("0.01"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2)
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(1, true, true, true, false, true, false)
    await pool.setFundingParams(1, rate("0.0002"), rate("0.0008"))

    // Asset 2 - another stable (not strict stable)
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(2, toBytes32("AST2"), 18, true, asset2.address, muxAsset0.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(2, rate("0.1"), rate("0.05"), rate("0.01"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 1)
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(2, true, true, true, false, true, false)
    await pool.setFundingParams(2, rate("0.0003"), rate("0.0009"))

    // Asset 3 - another position, useStable = true
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(3, toBytes32("AST3"), 18, false, "0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000")
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(3, rate("0.1"), rate("0.05"), rate("0.01"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2)
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(3, true, true, true, true, true, false)
    await pool.setFundingParams(3, rate("0.0002"), rate("0.0008"))

    await pool.setBlockTimestamp(3600 * 8 * 1)
  })

  it("invalid admin parameters", async () => {
    await expect(pool.setNumbers(3600 * 8, toWei("1"), toWei("2"), rate("1"), rate("0.000"))).to.revertedWith("F>1")
    await expect(pool.setAssetParams(100, rate("0.1"), rate("0.05"), rate("0.01"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2)).to.revertedWith(
      "LST"
    )
    await expect(pool.setAssetFlags(100, true, true, true, true, true, false)).to.revertedWith("LST")
    await expect(pool.setFundingParams(100, rate("0.0002"), rate("0.0008"))).to.revertedWith("LST")

    const mockChainlink = (await createContract("MockChainlink")) as MockChainlink
    await mockChainlink.setAnswer(toChainlink("100"))
    await expect(pool.setReferenceOracle(100, ReferenceOracleType.Chainlink, mockChainlink.address, rate("0.01"))).to.revertedWith("LST")
  })

  it("addLiquidity", async () => {
    const current = toWei("29700")
    const target = toWei("29700")
    await asset0.mint(user0.address, toWei("10000"))
    expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))

    // user 0 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await expect(pool.addLiquidity(user0.address, 0, toWei("100"), toWei("1"), toWei("0.1"), current, target)).to.revertedWith("MPO")
      await expect(pool.addLiquidity(user0.address, 0, toWei("100"), toWei("1"), toWei("2.1"), current, target)).to.revertedWith("MPO")
      await pool.addLiquidity(user0.address, 0, toWei("100"), toWei("1"), toWei("1"), current, target) // = 100 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999900"))
    }
    // user 0 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user0.address, 0, toWei("100"), toWei("1"), toWei("2"), current, target) // = 50 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("200"))
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("150"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999850"))
    }
    // user 1 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user1.address, 0, toWei("100"), toWei("1"), toWei("1"), current, target) // = 100 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("300"))
      expect(await mlp.balanceOf(user1.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999750"))
    }
    // user 1 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user1.address, 0, toWei("100"), toWei("2"), toWei("1"), current, target) // = 200 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("400"))
      expect(await mlp.balanceOf(user1.address)).to.equal(toWei("300"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999550"))
    }
  })

  it("removeLiquidity", async () => {
    const current = toWei("29700")
    const target = toWei("29700")

    // add liq
    await asset0.mint(pool.address, toWei("1000"))
    await asset1.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user0.address, 0, toWei("1000"), toWei("1"), toWei("1"), current, target) // = 100 mlp
    await pool.addLiquidity(user1.address, 1, toWei("1000"), toWei("1"), toWei("1"), current, target) // = 100 mlp
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("1000"))

    // remove liq
    await pool.removeLiquidity(user0.address, toWei("1"), 0, toWei("1"), toWei("1"), current, target)
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("1"))
    await pool.removeLiquidity(user0.address, toWei("100"), 0, toWei("2"), toWei("1"), current, target)
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("51"))
    await pool.removeLiquidity(user0.address, toWei("200"), 1, toWei("100"), toWei("1"), current, target)
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("51"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("2"))
  })

  it("depositCollateral / withdrawCollateral", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)

    await asset0.mint(pool.address, toWei("100"))
    await pool.depositCollateral(subAccountId, toWei("100"))
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("100"))

    await asset0.mint(pool.address, toWei("200"))
    await pool.depositCollateral(subAccountId, toWei("200"))
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("300"))

    await pool.withdrawCollateral(subAccountId, toWei("50"), toWei("1"), toWei("1"))
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("50"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("250"))
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("250"))
  })

  it("long/short stable coin. should fail", async () => {
    await expect(pool.openPosition(assembleSubAccountId(user0.address, 1, 0, true), toWei("1"), toWei("1"), toWei("100"))).to.revertedWith("STB")
    await expect(pool.openPosition(assembleSubAccountId(user0.address, 1, 0, false), toWei("1"), toWei("1"), toWei("100"))).to.revertedWith("STB")
  })

  it("open long, close long, take profit. profit = asset. 2 traders", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
    const subAccountId2 = assembleSubAccountId(user1.address, 0, 1, true)
    const current = toWei("29700")
    const target = toWei("29700")

    // lp = user1
    await asset0.mint(pool.address, toWei("1000"))
    await asset1.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 0, toWei("1000"), toWei("1"), toWei("1"), current, target)
    await pool.addLiquidity(user1.address, 1, toWei("1000"), toWei("100"), toWei("1"), current, target)

    // trader = user0, fee = 1
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId, toWei("11"))
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
      expect(assetInfo.spotLiquidity).to.equal(toWei("1000"))
      expect(assetInfo.collectedFee).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1001"))
      expect(collateralInfo.collectedFee).to.equal(toWei("1"))
    }

    // trader = user1, fee = 0.5
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId2, toWei("11"))
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
      expect(assetInfo.spotLiquidity).to.equal(toWei("1000"))
      expect(assetInfo.collectedFee).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1001.5"))
      expect(collateralInfo.collectedFee).to.equal(toWei("1.5"))
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
      expect(assetInfo.spotLiquidity).to.equal(toWei("999.51")) // += -((200 - 100) * 1 - fee) / 200
      expect(assetInfo.collectedFee).to.equal(toWei("0.01"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1001.5"))
      expect(collateralInfo.collectedFee).to.equal(toWei("1.5"))
    }

    // user1 50 => 50
    await pool.closePosition(subAccountId2, toWei("1"), 1, toWei("1"), toWei("50"), toWei("50"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0.49")) // fee = 0.5, pnl = 0
    {
      let subAccount = await pool.getSubAccount(subAccountId2)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      expect(assetInfo.spotLiquidity).to.equal(toWei("999.51"))
      expect(assetInfo.collectedFee).to.equal(toWei("0.01"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1002"))
      expect(collateralInfo.collectedFee).to.equal(toWei("2"))
    }
  })

  it("open long, close long, loss. 1 trader", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
    const current = toWei("29700")
    const target = toWei("29700")

    // trader = user0, fee = 1
    await asset0.mint(pool.address, toWei("102"))
    await pool.depositCollateral(subAccountId, toWei("102"))
    await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
    {
      let subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("101"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("100"))
      const collateral = await pool.getAssetInfo(0)
      expect(collateral.spotLiquidity).to.equal(toWei("1"))
      expect(collateral.collectedFee).to.equal(toWei("1"))
    }

    // trader = user0, fee = 0.995
    await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("99.5"))
    {
      let subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("100.005"))
      expect(subAccount.size).to.equal(toWei("2"))
      expect(subAccount.entryPrice).to.equal(toWei("99.75"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalLongPosition).to.equal(toWei("2"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("99.75"))
      const collateral = await pool.getAssetInfo(0)
      expect(collateral.spotLiquidity).to.equal(toWei("1.995"))
      expect(collateral.collectedFee).to.equal(toWei("1.995"))
    }

    // user0 99.75 => 95
    await pool.closePosition(subAccountId, toWei("1"), 1, toWei("1"), toWei("95"), toWei("95"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0")) // fee = 0.95, pnl = (95 - 99.75) * 1 = -4.75
    {
      let subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("94.305"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("99.75"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("99.75"))
      const collateral = await pool.getAssetInfo(0)
      expect(collateral.spotLiquidity).to.equal(toWei("7.695"))
      expect(collateral.collectedFee).to.equal(toWei("2.945"))
    }

    // user1 50 => 50
    await pool.closePosition(subAccountId, toWei("1"), 1, toWei("1"), toWei("95"), toWei("95"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0")) // fee = 0.95, pnl = (95 - 99.75) * 1 = -4.75
    {
      let subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("88.605"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      const collateral = await pool.getAssetInfo(0)
      expect(collateral.spotLiquidity).to.equal(toWei("13.395"))
      expect(collateral.collectedFee).to.equal(toWei("3.895"))
    }
  })

  it("open short, close short, take profit. profit = strict stable. 2 traders", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, false)
    const subAccountId2 = assembleSubAccountId(user1.address, 0, 1, false)
    const current = toWei("29700")
    const target = toWei("29700")

    // lp = user1
    await asset0.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 0, toWei("1000"), toWei("1"), toWei("1"), current, target)

    // trader = user0, fee = 1
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId, toWei("11"))
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
    await pool.depositCollateral(subAccountId2, toWei("11"))
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
    await expect(pool.closePosition(subAccountId, toWei("1"), 1, toWei("1"), toWei("50"), toWei("50"))).to.revertedWith("STB")
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("0"))
    await pool.closePosition(subAccountId, toWei("1"), 0, toWei("2"), toWei("50"), toWei("2")) // strict stable ignores price
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("49.5")) // fee = 0.5, ((100 - 50) * 1 - fee)
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
    await pool.closePosition(subAccountId2, toWei("1"), 0, toWei("2"), toWei("50"), toWei("2")) // strict stable ignores price
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

  it("open short, close short, take profit. profit = another stable", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, false)
    const subAccountId2 = assembleSubAccountId(user1.address, 0, 1, false)
    const current = toWei("29700")
    const target = toWei("29700")

    // lp = user1
    await asset2.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 2, toWei("1000"), toWei("1"), toWei("1"), current, target)

    // trader = user0, fee = 1
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId, toWei("11"))
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
    await pool.depositCollateral(subAccountId2, toWei("11"))
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
    await expect(pool.closePosition(subAccountId, toWei("1"), 1, toWei("50"), toWei("50"), toWei("50"))).to.revertedWith("STB")
    await pool.closePosition(subAccountId, toWei("1"), 2, toWei("1"), toWei("50"), toWei("2")) // un-strict stable uses price
    expect(await asset2.balanceOf(user0.address)).to.equal(toWei("24.75")) // fee = 0.5, ((100 - 50) * 1 - fee) / 2
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
    await pool.closePosition(subAccountId2, toWei("1"), 2, toWei("1"), toWei("50"), toWei("2")) // un-strict stable uses price
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
    const current = toWei("29700")
    const target = toWei("29700")

    // lp = user1
    await asset2.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 2, toWei("1000"), toWei("1"), toWei("1"), current, target)

    // trader = user0
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId, toWei("11"))
    // fee = 100 * 1% = 1
    await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("10"))
    expect(subAccount.size).to.equal(toWei("1"))
    expect(subAccount.entryPrice).to.equal(toWei("100"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))

    // 100 => 200
    await expect(pool.closePosition(subAccountId, toWei("1"), 1, toWei("1"), toWei("200"), toWei("200"))).to.revertedWith("STB")
    await pool.closePosition(subAccountId, toWei("1"), 2, toWei("1"), toWei("200"), toWei("1"))
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("10"))
    expect(subAccount.size).to.equal(toWei("0"))
    expect(subAccount.entryPrice).to.equal(toWei("0"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))
    expect(await asset2.balanceOf(user0.address)).to.equal(toWei("98")) // fee = 2, ((200 - 100) * 1 - fee)
  })

  it("close long. pnl < min profit", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
    const current = toWei("29700")
    const target = toWei("29700")

    // lp = user1
    await asset1.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 1, toWei("1000"), toWei("1"), toWei("1"), current, target)

    // trader = user0
    await pool.depositCollateral(subAccountId, toWei("11"))
    // fee = 100 * 1% = 1
    await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
    {
      const subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("10"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
    }
    {
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("1")) // += fee
      expect(assetInfo.collectedFee).to.equal(toWei("1"))
    }

    // 100 => 100.5
    await pool.closePosition(subAccountId, toWei("0.1"), 1, toWei("1"), toWei("100.5"), toWei("0"))
    {
      const subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("9.8995")) // fee = 0.1005, pnl = 0
      expect(subAccount.size).to.equal(toWei("0.9"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0"))
      expect(await asset0.balanceOf(user0.address)).to.equal(toWei("0"))
    }
    {
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("1.1005")) // += fee
      expect(assetInfo.collectedFee).to.equal(toWei("1.1005"))
    }

    // long enough. pnl < fee
    await pool.setBlockTimestamp(3600 * 8 * 10)
    await pool.closePosition(subAccountId, toWei("0.1"), 1, toWei("1"), toWei("100.5"), toWei("0"))
    {
      const subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("9.849")) // fee = 0.1005, pnl = 0.05
      expect(subAccount.size).to.equal(toWei("0.8"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0"))
      expect(await asset0.balanceOf(user0.address)).to.equal(toWei("0"))
    }
    {
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("1.151")) // += fee - pnl
      expect(assetInfo.collectedFee).to.equal(toWei("1.151"))
    }
  })

  it("0 < fee < margin < MM. liquidate short", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, false)

    // trader = user0
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId, toWei("11"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("11"))

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

    // 100 => 105
    await expect(pool.liquidate(subAccountId, 1, toWei("1"), toWei("100"), toWei("100"))).to.revertedWith("STB")
    await expect(pool.liquidate(subAccountId, 0, toWei("1"), toWei("100"), toWei("1"))).to.revertedWith("MMS")
    await pool.liquidate(subAccountId, 0, toWei("1"), toWei("105"), toWei("1")) // fee = 1.05, pnl = -5
    var subAccount = await pool.getSubAccount(subAccountId)
    expect(subAccount.collateral).to.equal(toWei("3.95")) // 10 - 5 - 1.05
    expect(subAccount.size).to.equal(toWei("0"))
    expect(subAccount.entryPrice).to.equal(toWei("0"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("11"))
    {
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("7.05")) // += fee - pnl
      expect(assetInfo.collectedFee).to.equal(toWei("2.05"))
    }
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
    }
  })

  it("0 < margin < fee < MM. liquidate short", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, false)

    // trader = user0
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId, toWei("11"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("11"))

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

    // 100 => 109
    await pool.liquidate(subAccountId, 0, toWei("1"), toWei("109"), toWei("1"))
    var subAccount = await pool.getSubAccount(subAccountId) // fee = 1 (original 1.09), pnl = -9
    expect(subAccount.collateral).to.equal(toWei("0"))
    expect(subAccount.size).to.equal(toWei("0"))
    expect(subAccount.entryPrice).to.equal(toWei("0"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("11"))
    {
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("11")) // += fee - pnl
      expect(assetInfo.collectedFee).to.equal(toWei("2"))
    }
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
    }
  })

  it("margin < 0. liquidate short", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, false)

    // trader = user0
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(subAccountId, toWei("11"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("11"))

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

    // 100 => 111
    await expect(pool.closePosition(subAccountId, toWei("1"), 0, toWei("1"), toWei("111"), toWei("1"))).to.revertedWith("M=0")
    await pool.liquidate(subAccountId, 0, toWei("1"), toWei("111"), toWei("1"))
    var subAccount = await pool.getSubAccount(subAccountId) // fee = 0 (original 1.11), pnl = -10 (original -11)
    expect(subAccount.collateral).to.equal(toWei("0"))
    expect(subAccount.size).to.equal(toWei("0"))
    expect(subAccount.entryPrice).to.equal(toWei("0"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("11"))
    {
      const assetInfo = await pool.getAssetInfo(0)
      expect(assetInfo.spotLiquidity).to.equal(toWei("11")) // += fee - pnl
      expect(assetInfo.collectedFee).to.equal(toWei("1"))
    }
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
    }
  })

  it("updateFundingState", async () => {
    await pool.setBlockTimestamp(3600 * 8 * 10 + 600) // should truncate
    await pool.updateFundingState(rate("0"), [1, 3], [rate("0"), rate("0")], [toWei("100"), toWei("300")])

    // init
    {
      const storage = await pool.getLiquidityPoolStorage()
      expect(storage.u32s[0]).to.eq(rate("0.0003")) // shortFundingBaseRate8H
      expect(storage.u32s[1]).to.eq(rate("0.0009")) // shortFundingLimitRate8H
      expect(storage.u32s[2]).to.eq(3600 * 8 * 10) // lastFundingTime
    }
    {
      const assets = await pool.getAllAssetInfo()
      expect(assets[1].longFundingBaseRate8H).to.eq(rate("0.0002"))
      expect(assets[1].longFundingLimitRate8H).to.eq(rate("0.0008"))
      expect(assets[1].longCumulativeFundingRate).to.eq(toWei("0"))
      expect(assets[1].shortCumulativeFunding).to.eq(toWei("0"))
      expect(assets[3].longFundingBaseRate8H).to.eq(rate("0.0002"))
      expect(assets[3].longFundingLimitRate8H).to.eq(rate("0.0008"))
      expect(assets[3].longCumulativeFundingRate).to.eq(toWei("0"))
      expect(assets[3].shortCumulativeFunding).to.eq(toWei("0"))
    }

    await pool.setBlockTimestamp(3600 * 8 * 11 + 900) // should truncate
    await pool.updateFundingState(rate("0.5"), [1, 3], [rate("0.5"), rate("1")], [toWei("100"), toWei("300")])
    {
      const storage = await pool.getLiquidityPoolStorage()
      expect(storage.u32s[2]).to.eq(3600 * 8 * 11) // lastFundingTime
    }
    {
      const assets = await pool.getAllAssetInfo()
      expect(assets[1].longCumulativeFundingRate).to.eq(toWei("0.0004"))
      expect(assets[1].shortCumulativeFunding).to.eq(toWei("0.045")) // 0.00045 * 100
      expect(assets[3].longCumulativeFundingRate).to.eq(toWei("0.0008"))
      expect(assets[3].shortCumulativeFunding).to.eq(toWei("0.135")) // 0.00045 * 100
    }
  })

  describe("muxToken", async () => {
    it("close long, profit in muxBtc, and redeem muxBtc", async () => {
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
      const current = toWei("29700")
      const target = toWei("29700")

      // trader = user0
      await asset0.mint(pool.address, toWei("11"))
      await pool.depositCollateral(subAccountId, toWei("11"))

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
      await pool.addLiquidity(user1.address, 1, toWei("1000"), toWei("100"), toWei("1"), current, target)

      // redeem muxBtc
      await pool.redeemMuxToken(user0.address, 1, toWei("0.49"))
      expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0.49"))
    })
    it("close short, profit in muxUsd, and redeem muxUsd", async () => {
      const subAccountId = assembleSubAccountId(user0.address, 1, 1, false)
      const current = toWei("29700")
      const target = toWei("29700")

      // trader = user0
      await asset0.mint(pool.address, toWei("1"))
      await pool.depositCollateral(subAccountId, toWei("1"))

      // fee = 100 * 1% / 100 = 0.01
      await pool.openPosition(subAccountId, toWei("1"), toWei("100"), toWei("100"))
      var subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("0.99"))
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("100"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))

      // 100 => 200
      await pool.closePosition(subAccountId, toWei("1"), 0, toWei("50"), toWei("50"), toWei("1"))
      var subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("0.99"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      expect(await muxAsset0.balanceOf(user0.address)).to.equal(toWei("49.5")) // fee = 0.5, ((100 - 50) * 1 - fee) / 1
      expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0"))

      // redeem muxUsd
      await expect(pool.redeemMuxToken(user0.address, 2, toWei("98"))).to.revertedWith("STR") // only strict stable coin can be redeemed
      await expect(pool.redeemMuxToken(user0.address, 0, toWei("98"))).to.revertedWith("LIQ")

      // deposit liquidity, lp = user1
      await asset0.mint(pool.address, toWei("1000"))
      await pool.addLiquidity(user1.address, 0, toWei("1000"), toWei("1"), toWei("1"), current, target)

      // redeem muxUsd
      await pool.redeemMuxToken(user0.address, 0, toWei("98"))
      expect(await asset0.balanceOf(user0.address)).to.equal(toWei("98"))
    })
  })

  describe("withdrawProfit", async () => {
    it("open long, withdrawProfit. profit = asset", async () => {
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
      const current = toWei("29700")
      const target = toWei("29700")

      // lp = user1
      await asset0.mint(pool.address, toWei("1000"))
      await asset1.mint(pool.address, toWei("1000"))
      await pool.addLiquidity(user1.address, 0, toWei("1000"), toWei("1"), toWei("1"), current, target)
      await pool.addLiquidity(user1.address, 1, toWei("1000"), toWei("100"), toWei("1"), current, target)

      // trader = user0
      await asset0.mint(pool.address, toWei("16"))
      await pool.depositCollateral(subAccountId, toWei("16"))

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
      const current = toWei("29700")
      const target = toWei("29700")

      // lp = user1
      await asset2.mint(pool.address, toWei("1000"))
      await pool.addLiquidity(user1.address, 2, toWei("1000"), toWei("1"), toWei("1"), current, target)

      // trader = user0
      await asset0.mint(pool.address, toWei("11"))
      await pool.depositCollateral(subAccountId, toWei("11"))

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
      await expect(pool.withdrawProfit(subAccountId, toWei("50"), 1, toWei("1"), toWei("50"), toWei("50"))).to.revertedWith("STB")
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
      await pool.depositCollateral(subAccountId, toWei("101"))
      const tx1 = await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
      await expect(tx1)
        .to.emit(pool, "OpenPosition")
        .withArgs(user0.address, 1, [subAccountId, 0, true, toWei("1"), toWei("100"), toWei("1"), toWei("100"), toWei("1")])
    })

    it("higher reference price", async () => {
      await mockChainlink.setAnswer(toChainlink("200"))
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)

      // trader = user0
      await asset0.mint(pool.address, toWei("101"))
      await pool.depositCollateral(subAccountId, toWei("101"))
      const tx1 = await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
      await expect(tx1)
        .to.emit(pool, "OpenPosition")
        .withArgs(user0.address, 1, [subAccountId, 0, true, toWei("1"), toWei("198"), toWei("1"), toWei("198"), toWei("1.98")])
    })

    it("lower reference price", async () => {
      await mockChainlink.setAnswer(toChainlink("1"))
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)

      // trader = user0
      await asset0.mint(pool.address, toWei("101"))
      await pool.depositCollateral(subAccountId, toWei("101"))
      const tx1 = await pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))
      await expect(tx1)
        .to.emit(pool, "OpenPosition")
        .withArgs(user0.address, 1, [subAccountId, 0, true, toWei("1"), toWei("1.01"), toWei("1"), toWei("1.01"), toWei("0.0101")])
    })
  })

  it("pauseAll", async () => {
    await expect(pool.connect(user1).pauseAll()).to.revertedWith("Ownable: caller is not the owner")
    await pool.pauseAll()

    const current = toWei("29700")
    const target = toWei("29700")
    await expect(pool.addLiquidity(user0.address, 0, toWei("100"), toWei("1"), toWei("1"), current, target)).to.revertedWith("ENA")
    await expect(pool.removeLiquidity(user0.address, toWei("1"), 0, toWei("1"), toWei("1"), current, target)).to.revertedWith("ENA")

    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
    await expect(pool.depositCollateral(subAccountId, toWei("200"))).to.revertedWith("ENA")
    await expect(pool.withdrawCollateral(subAccountId, toWei("50"), toWei("1"), toWei("1"))).to.revertedWith("ENA")

    await expect(pool.openPosition(subAccountId, toWei("1"), toWei("1"), toWei("100"))).to.revertedWith("ENA")
    await expect(pool.closePosition(subAccountId, toWei("1"), 0, toWei("2"), toWei("50"), toWei("2"))).to.revertedWith("ENA")
  })
})
