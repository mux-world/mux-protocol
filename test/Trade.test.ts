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
  AdminParamsAbi,
  AdminParamsType,
} from "./deployUtils"
const U = ethers.utils

describe("Trade", () => {
  let mlp: Contract
  let pool: Contract
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
    const LibMuxAdmin = await createContract("LibMuxAdmin")
    pool = await createContract("LiquidityPool", [], { LibMuxAdmin })
    mlp = await createContract("MockERC20", ["MLP", "MLP", 18])
    await mlp.mint(pool.address, toWei(PreMinedTokenTotalSupply))
    await pool.initialize(mlp.address)

    asset0 = await createContract("MockERC20", ["AST0", "AST0", 18])
    asset1 = await createContract("MockERC20", ["AST1", "AST1", 18])

    // id, symbol, decimals, stable, token, pool
    await pool.setParams(
      AdminParamsType.AddAsset,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.AddAsset, [
        0,
        toBytes32("AST0"),
        18,
        false,
        asset0.address,
        asset0.address,
      ])
    )
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setParams(
      AdminParamsType.SetAssetParams,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetParams, [
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
        0,
      ])
    )
    // id, tradable, openable, shortable, useStable
    await pool.setParams(
      AdminParamsType.SetAssetFlags,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetFlags, [0, true, true, true, false])
    )

    // id, symbol, decimals, stable, token, pool
    await pool.setParams(
      AdminParamsType.AddAsset,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.AddAsset, [
        1,
        toBytes32("AST1"),
        18,
        false,
        asset1.address,
        asset1.address,
      ])
    )
    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
    await pool.setParams(
      AdminParamsType.SetAssetParams,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetParams, [
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
        0,
      ])
    )
    // id, tradable, openable, shortable, useStable
    await pool.setParams(
      AdminParamsType.SetAssetFlags,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetFlags, [1, true, true, true, false])
    )

    // only for test purpose
    await pool.setParams(
      AdminParamsType.SetAddresses,
      ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAddresses, [user0.address, user0.address])
    )
  })

  it("addLiquidity", async () => {
    await asset0.mint(user0.address, toWei("10000"))
    expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))

    await asset0.transfer(pool.address, toWei("100"))
    await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("1")) // = 100 mlp
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("100"))
    expect(await mlp.balanceOf(user0.address)).to.equal(toWei("100"))
    expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999900"))

    await asset0.transfer(pool.address, toWei("100"))
    await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("2")) // = 100 mlp
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("200"))
    expect(await mlp.balanceOf(user0.address)).to.equal(toWei("150"))
    expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999850"))

    await asset0.transfer(pool.address, toWei("100"))
    await pool.addLiquidity(user1.address, 0, toWei("1"), toWei("1")) // = 100 mlp
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("300"))
    expect(await mlp.balanceOf(user1.address)).to.equal(toWei("100"))
    expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999750"))

    await asset0.transfer(pool.address, toWei("100"))
    await pool.addLiquidity(user1.address, 0, toWei("2"), toWei("1")) // = 100 mlp
    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("400"))
    expect(await mlp.balanceOf(user1.address)).to.equal(toWei("300"))
    expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999550"))
  })

  it("removeLiquidity", async () => {
    await asset0.mint(pool.address, toWei("1000"))
    await asset1.mint(pool.address, toWei("1000"))

    await pool.addLiquidity(user0.address, 0, toWei("1"), toWei("1")) // = 100 mlp
    await pool.addLiquidity(user1.address, 1, toWei("1"), toWei("1")) // = 100 mlp

    expect(await asset0.balanceOf(pool.address)).to.equal(toWei("1000"))

    await asset0.approve(user0.address, toWei("0"))

    await pool.removeLiquidity(user0.address, toWei("1"), 0, toWei("1"), toWei("1"))
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("1"))

    await pool.removeLiquidity(user0.address, toWei("100"), 0, toWei("2"), toWei("1"))
    expect(await asset0.balanceOf(user0.address)).to.equal(toWei("51"))

    await pool.removeLiquidity(user0.address, toWei("200"), 1, toWei("100"), toWei("1"))
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
    // lp = user1
    await asset0.mint(pool.address, toWei("1000"))
    await asset1.mint(pool.address, toWei("1000"))
    await pool.addLiquidity(user1.address, 0, toWei("1"), toWei("1")) // = 100 mlp
    await pool.addLiquidity(user1.address, 1, toWei("100"), toWei("1")) // = 100 mlp

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
    await pool.closePosition(
      assembleSubAccountId(user0.address, 0, 1, true),
      toWei("1"),
      1,
      toWei("1"),
      toWei("200"),
      toWei("200")
    )
    var subAccount = await pool.getSubAccount(assembleSubAccountId(user0.address, 0, 1, true))
    expect(subAccount.collateral).to.equal(toWei("10"))
    expect(subAccount.size).to.equal(toWei("0"))
    expect(subAccount.entryPrice).to.equal(toWei("0"))
    expect(subAccount.entryFunding).to.equal(toWei("0"))
    expect(await asset1.balanceOf(user0.address)).to.equal(toWei("0.49")) // (100 - 2) / 200
  })
})

// TODO: withdraw collateral when position = 0
// TODO: useStableTokenForProfit
// TODO: liquidate
