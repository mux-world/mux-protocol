import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, createContract, toBytes32, rate, assembleSubAccountId, PreMinedTokenTotalSupply, createFactory } from "./deployUtils"
import { TestLiquidityPool } from "../typechain"
const U = ethers.utils

describe("Trade", () => {
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  let mlp: Contract
  let pool: TestLiquidityPool
  let asset0: Contract
  let asset1: Contract

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
    await pool.initialize(poolHop2.address, mlp.address, user0.address /* test only */, user0.address /* test only */, weth9)
    // fundingInterval, liquidityLockPeriod
    await pool.setNumbers(8 * 3600, 0)

    asset0 = await createContract("MockERC20", ["AST0", "AST0", 18])
    asset1 = await createContract("MockERC20", ["AST1", "AST1", 18])

    // Asset 0 - stable
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("AST0"), 18, true, asset0.address, asset0.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setAssetParams(
      0,
      rate("0.1"),
      rate("0.05"),
      rate("0.01"),
      rate("0.01"),
      10,
      toWei("10000000"),
      toWei("10000000"),
      1,
      "0x0000000000000000000000000000000000000000",
      0
    )
    // id, tradable, openable, shortable, useStable
    await pool.setAssetFlags(0, true, true, true, false)
    await pool.setFundingParams(0, rate("0.0003"), rate("0.0009"))

    // Asset 1
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(1, toBytes32("AST1"), 18, false, asset1.address, asset1.address)
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setAssetParams(
      1,
      rate("0.1"),
      rate("0.05"),
      rate("0.01"),
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
    await pool.setFundingParams(1, rate("0.0002"), rate("0.0008"))
  })

  it("addLiquidity", async () => {
    const feeRate1 = rate("0")
    await asset0.mint(user0.address, toWei("10000"))
    expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))

    // user 0 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))

      await pool.claimMLP()
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999900"))
    }
    // user 0 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("2"), feeRate1) // = 50 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("200"))
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999900"))

      await pool.claimMLP()
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("150"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999850"))
    }
    // user 1 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user1.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("300"))
      expect(await mlp.balanceOf(user1.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999850"))

      await pool.connect(user1).claimMLP()
      expect(await mlp.balanceOf(user1.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999750"))
    }
    // user 1 +liq
    {
      await asset0.transfer(pool.address, toWei("100"))
      await pool.addLiquidity(user1.address, 0, toWei("2"), toWei("1"), feeRate1) // = 200 mlp
      expect(await asset0.balanceOf(pool.address)).to.equal(toWei("400"))
      expect(await mlp.balanceOf(user1.address)).to.equal(toWei("100"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999750"))

      await pool.connect(user1).claimMLP()
      expect(await mlp.balanceOf(user1.address)).to.equal(toWei("300"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999550"))
    }
  })

  it("removeLiquidity", async () => {
    const feeRate1 = rate("0")
    await asset0.mint(pool.address, toWei("1000"))
    await asset1.mint(pool.address, toWei("1000"))

    await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
    await pool.addLiquidity(user1.address, 1, toWei("1"), toWei("1"), feeRate1) // = 100 mlp

    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("1000"))

    await asset0.approve(user0.address, toWei("0"))

    await pool.removeLiquidity(user0.address, toWei("1"), 0, toWei("1"), toWei("1"), feeRate1)
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("1"))

    await pool.removeLiquidity(user0.address, toWei("100"), 0, toWei("2"), toWei("1"), feeRate1)
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("51"))

    await pool.removeLiquidity(user0.address, toWei("200"), 1, toWei("100"), toWei("1"), feeRate1)
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("51"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("2"))
  })

  it("depositCollateral / withdrawCollateral", async () => {
    await asset0.mint(pool.address, toWei("100"))
    await pool.depositCollateral(assembleSubAccountId(user0.address, 0, 1, true))
    var subAccount = await pool.getSubAccount(assembleSubAccountId(user0.address, 0, 1, true))
    expect(subAccount.collateral).to.equal(toWei("100"))

    await asset0.mint(pool.address, toWei("200"))
    await pool.depositCollateral(assembleSubAccountId(user0.address, 0, 1, true))
    var subAccount = await pool.getSubAccount(assembleSubAccountId(user0.address, 0, 1, true))
    expect(subAccount.collateral).to.equal(toWei("300"))

    await pool.withdrawCollateral(assembleSubAccountId(user0.address, 0, 1, true), toWei("50"), toWei("1"), toWei("1"))
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("50"))
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("250"))
    var subAccount = await pool.getSubAccount(assembleSubAccountId(user0.address, 0, 1, true))
    expect(subAccount.collateral).to.equal(toWei("250"))
  })

  it("openPosition / closePosition -- long", async () => {
    const feeRate1 = rate("0")

    // lp = user1
    await asset0.mint(pool.address, toWei("1000"))
    await asset1.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 0, toWei("1"), toWei("1"), feeRate1) // = 100 mlp
    await pool.addLiquidity(user1.address, 1, toWei("100"), toWei("1"), feeRate1) // = 100 mlp

    // trader = user0
    await asset0.mint(pool.address, toWei("11"))
    await pool.depositCollateral(assembleSubAccountId(user0.address, 0, 1, true))

    // collateral = 11, fee = 100 * 1% = 1, total = 10
    await pool.openPosition(assembleSubAccountId(user0.address, 0, 1, true), toWei("1"), toWei("1"), toWei("100"))

    var subAccount = await pool.getSubAccount(assembleSubAccountId(user0.address, 0, 1, true))
    expect(subAccount.collateral).to.equal(toWei("10"))
    expect(subAccount.size).to.equal(toWei("1"))
    expect(subAccount.entryPrice).to.equal(toWei("100"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))

    // 100 => 200
    await pool.closePosition(assembleSubAccountId(user0.address, 0, 1, true), toWei("1"), 1, toWei("1"), toWei("200"), toWei("200"))
    var subAccount = await pool.getSubAccount(assembleSubAccountId(user0.address, 0, 1, true))
    expect(subAccount.collateral).to.equal(toWei("10"))
    expect(subAccount.size).to.equal(toWei("0"))
    expect(subAccount.entryPrice).to.equal(toWei("0"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0.49")) // (100 - 2) / 200
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
    await pool.updateFundingState(rate("0"), [1], [rate("0")])

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
    }
    await pool.setBlockTimestamp(3600 * 8 * 11 + 900) // should truncate
    await pool.updateFundingState(rate("0.5"), [1], [rate("0.5")])
    {
      const storage = await pool.getLiquidityPoolStorage()
      expect(storage.u32s[2]).to.eq(3600 * 8 * 11) // lastFundingTime
      expect(storage.u128s[0]).to.eq(toWei("0.00045")) // shortCumulativeFunding
    }
    {
      const assets = await pool.getAllAssetInfo()
      expect(assets[1].longCumulativeFunding).to.eq(toWei("0.0004"))
    }
  })
})

// TODO: useStableTokenForProfit
// TODO: liquidate
