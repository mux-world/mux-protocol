import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { BigNumber, Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, rate, PreMinedTokenTotalSupply, createFactory } from "./deployUtils"
import { createContract, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { MlpToken, TestOrderBook, TestLiquidityPool, LiquidityManager, Reader } from "../typechain"
const U = ethers.utils

describe("Borrow", () => {
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let usdc: Contract
  let wbnb: Contract
  let muxUsd: Contract
  let muxBnb: Contract

  let lp1: SignerWithAddress
  let admin: SignerWithAddress

  before(async () => {
    const accounts = await ethers.getSigners()
    if (accounts.length < 3) {
      throw new Error("BscCompatible test requires 3 addresses")
    }
    admin = accounts[0]
    lp1 = accounts[1]
  })

  beforeEach(async () => {
    const libLiquidity = await createContract("LibLiquidity")
    const poolHop1 = await createContract("TestLiquidityPoolHop1")
    const poolHop2 = await createContract("TestLiquidityPoolHop2", [], { "contracts/libraries/LibLiquidity.sol:LibLiquidity": libLiquidity })
    pool = await ethers.getContractAt("TestLiquidityPool", poolHop1.address)
    mlp = (await createContract("MlpToken")) as MlpToken
    await mlp.initialize("MLP", "MLP")
    await pool.initialize(poolHop2.address, mlp.address, admin.address, weth9, weth9, admin.address)
    await pool.setLiquidityManager(admin.address, true)
    // fundingInterval, liqBase, liqDyn, σ_strict, brokerGas
    await pool.setNumbers(3600 * 8, rate("0.0001"), rate("0.0000"), rate("0.01"), toWei("0"))
    // mlpPrice, mlpPrice
    await pool.setEmergencyNumbers(toWei("1"), toWei("2000"))
    await mlp.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    usdc = await createContract("MockERC20", ["Usdc", "Usdc", 6])
    wbnb = await createContract("MockERC20", ["Wbnb", "Wbnb", 18])

    muxUsd = await createContract("MuxToken")
    await muxUsd.initialize("muxUsd", "muxUsd")
    await muxUsd.transfer(pool.address, toWei(PreMinedTokenTotalSupply))
    muxBnb = await createContract("MuxToken")
    await muxBnb.initialize("muxBnb", "muxBnb")
    await muxBnb.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    // 0 = USDC
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("USDC"), 6, true, usdc.address, muxUsd.address)
    // id, symbol, imr, mmr, fee, fee, minBps, minTime, maxLong, maxShort, spotWeight, halfSpread
    await pool.setAssetParams(0, toBytes32("USDC"), rate("0"), rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1, rate("0"))
    // id, tradable, openable, shortable, useStable, enabled, strict, liq
    await pool.setAssetFlags(0, false, false, false, false, true, true, true)
    await pool.setFundingParams(0, rate("0.0002"), rate("0.0008"))

    // 1 = BNB
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(1, toBytes32("BNB"), 18, false, wbnb.address, muxBnb.address)
    // id, symbol, imr, mmr, fee, fee, minBps, minTime, maxLong, maxShort, spotWeight, halfSpread
    await pool.setAssetParams(1, toBytes32("BNB"), rate("0.1"), rate("0.05"), rate("0.001"), rate("0.002"), rate("0.01"), 10, toWei("10000000"), toWei("10000000"), 2, rate("0"))
    // id, tradable, openable, shortable, useStable, enabled, strict, liq
    await pool.setAssetFlags(1, true, true, true, false, true, false, true)
    await pool.setFundingParams(1, rate("0.0003"), rate("0.0009"))

    await pool.setBlockTimestamp(86400 * 1)
    await pool.setBlockTimestamp(86400 * 2)

    // add liq
    await usdc.mint(pool.address, toUnit("1000000", 6))
    await pool.addLiquidity(lp1.address, 0, toUnit("1000000", 6), toWei("1"), toWei("1"), toWei("0"), toWei("1000000"))
    await wbnb.mint(pool.address, toWei("1000000"))
    await pool.addLiquidity(lp1.address, 1, toWei("1000"), toWei("300"), toWei("1"), toWei("0"), toWei("1000"))
  })

  it("decimals 18", async () => {
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.collectedFee).to.equal(toWei("0.1"))
      expect(assetInfo.spotLiquidity).to.equal(toWei("1000"))
      expect(assetInfo.credit).to.equal(toWei("0"))
    }
    expect(await wbnb.balanceOf(admin.address)).to.equal(toWei("0"))
    await pool.borrowAsset(admin.address, 1, toWei("100"), toWei("1"))
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.collectedFee).to.equal(toWei("1.1"))
      expect(assetInfo.spotLiquidity).to.equal(toWei("901"))
      expect(assetInfo.credit).to.equal(toWei("100"))
    }
    expect(await wbnb.balanceOf(admin.address)).to.equal(toWei("99"))
    await wbnb.mint(admin.address, toWei("2"))
    await wbnb.transfer(pool.address, toWei("101"))
    await pool.repayAsset(admin.address, 1, toWei("100"), toWei("1"), toWei("0"))
    {
      const assetInfo = await pool.getAssetInfo(1)
      expect(assetInfo.collectedFee).to.equal(toWei("2.1"))
      expect(assetInfo.spotLiquidity).to.equal(toWei("1002"))
      expect(assetInfo.credit).to.equal(toWei("0"))
    }
  })

  //   it("decimals 6", async () => {
  //     {
  //       const assetInfo = await pool.getAssetInfo(0)
  //       expect(assetInfo.collectedFee).to.equal(toWei("100"))
  //       expect(assetInfo.spotLiquidity).to.equal(toWei("1000000"))
  //       expect(assetInfo.credit).to.equal(toWei("0"))
  //     }
  //     expect(await usdc.balanceOf(admin.address)).to.equal(toUnit("0", 6))
  //     await pool.borrowAsset(admin.address, 0, toUnit("100", 6), toUnit("1", 6))
  //     {
  //       const assetInfo = await pool.getAssetInfo(0)
  //       expect(assetInfo.collectedFee).to.equal(toWei("101"))
  //       expect(assetInfo.spotLiquidity).to.equal(toWei("999999"))
  //       expect(assetInfo.credit).to.equal(toWei("100"))
  //     }
  //     expect(await wbnb.balanceOf(admin.address)).to.equal(toWei("99"))
  //     await usdc.mint(admin.address, toUnit("2", 6))
  //     await usdc.transfer(pool.address, toUnit("101", 6))
  //     await pool.repayAsset(admin.address, 0, toUnit("100", 6), toUnit("1", 6), toUnit("0", 6))
  //     {
  //       const assetInfo = await pool.getAssetInfo(0)
  //       expect(assetInfo.collectedFee).to.equal(toWei("102"))
  //       expect(assetInfo.spotLiquidity).to.equal(toWei("1000002"))
  //       expect(assetInfo.credit).to.equal(toWei("0"))
  //     }
  //   })
})
