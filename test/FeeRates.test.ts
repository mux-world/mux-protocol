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
const U = ethers.utils

describe("FeeRates", () => {
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
    await pool.initialize(poolHop2.address, mlp.address, user0.address /* test only */, user0.address /* test only */, weth9, weth9, user0.address /* vault */)
    // fundingInterval, liqBase, liqDyn, σ_strict, brokerGas
    await pool.setNumbers(3600 * 8, rate("0.0001"), rate("0.0000"), rate("0.01"), toWei("0"))
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

  describe("getLiquidityFeeRate", () => {
    it("current 29700, target 29700", async () => {
      const current = toWei("29700")
      const target = toWei("29700")
      let base = rate("0.00100")
      let dynamic = rate("0.00050")
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("1000"), base, dynamic)).to.equal(rate("0.00100"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("5000"), base, dynamic)).to.equal(rate("0.00104"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("1000"), base, dynamic)).to.equal(rate("0.00100"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("5000"), base, dynamic)).to.equal(rate("0.00104"))
      base = rate("0.00050")
      dynamic = rate("0.00100")
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("1000"), base, dynamic)).to.equal(rate("0.00051"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("5000"), base, dynamic)).to.equal(rate("0.00058"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("1000"), base, dynamic)).to.equal(rate("0.00051"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("5000"), base, dynamic)).to.equal(rate("0.00058"))
    })
    it("current 29700, target 14850", async () => {
      const current = toWei("29700")
      const target = toWei("14850")
      let base = rate("0.00100")
      let dynamic = rate("0.00050")
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("1000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("5000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("10000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("20000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("1000"), base, dynamic)).to.equal(rate("0.00050"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("5000"), base, dynamic)).to.equal(rate("0.00050"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("10000"), base, dynamic)).to.equal(rate("0.00050"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("20000"), base, dynamic)).to.equal(rate("0.00050"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("25000"), base, dynamic)).to.equal(rate("0.00050"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("29700"), base, dynamic)).to.equal(rate("0.00150"))
    })
    it("current 29700, target 37270", async () => {
      const current = toWei("29700")
      const target = toWei("37270")
      let base = rate("0.00100")
      let dynamic = rate("0.00050")
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("1000"), base, dynamic)).to.equal(rate("0.00090"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("5000"), base, dynamic)).to.equal(rate("0.00090"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("10000"), base, dynamic)).to.equal(rate("0.00090"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("1000"), base, dynamic)).to.equal(rate("0.00110"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("5000"), base, dynamic)).to.equal(rate("0.00113"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("10000"), base, dynamic)).to.equal(rate("0.00116"))
    })
    it("current 88800, target 36266", async () => {
      const current = toWei("88800")
      const target = toWei("36266")
      let base = rate("0.00100")
      let dynamic = rate("0.00050")
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("1000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("5000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("10000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("1000"), base, dynamic)).to.equal(rate("0.00028"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("5000"), base, dynamic)).to.equal(rate("0.00028"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("20000"), base, dynamic)).to.equal(rate("0.00028"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("50000"), base, dynamic)).to.equal(rate("0.00028"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("80000"), base, dynamic)).to.equal(rate("0.00028"))
      base = rate("0.00050")
      dynamic = rate("0.00100")
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("1000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("5000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("10000"), base, dynamic)).to.equal(rate("0.00150"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("1000"), base, dynamic)).to.equal(rate("0.00000"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("5000"), base, dynamic)).to.equal(rate("0.00000"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("20000"), base, dynamic)).to.equal(rate("0.00000"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("50000"), base, dynamic)).to.equal(rate("0.00000"))
    })
    it("current 29700, target 0", async () => {
      const current = toWei("29700")
      const target = toWei("0")
      let base = rate("0.00100")
      let dynamic = rate("0.00050")
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("1000"), base, dynamic)).to.equal(rate("0.00100"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, true, toWei("5000"), base, dynamic)).to.equal(rate("0.00100"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("1000"), base, dynamic)).to.equal(rate("0.00100"))
      expect(await pool.getLiquidityFeeRatePublic(current, target, false, toWei("5000"), base, dynamic)).to.equal(rate("0.00100"))
    })
  })
})
