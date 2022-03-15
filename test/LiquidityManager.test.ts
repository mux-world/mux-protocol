import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, OrderType, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber } from "@ethersproject/bignumber"
const U = ethers.utils

describe("LiquidityManager", () => {
  let pool: Contract
  let mlp: Contract
  let tokenA: Contract
  let tokenB: Contract
  let lm: Contract
  let uniV2: Contract
  let lp: Contract
  let uv2conn: Contract

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
    tokenA = await createContract("MockERC20", ["TokenA", "TokenA", 18])
    tokenB = await createContract("MockERC20", ["TokenB", "TokenB", 18])
    mlp = await createContract("MockERC20", ["MLP", "MLP", 18])

    pool = await createContract("MockLiquidityPool")

    // asset 0
    await pool.setAssetAddress(0, tokenA.address)
    // asset 1
    await pool.setAssetAddress(1, tokenB.address)

    lm = await createContract("LiquidityManager")
    await lm.initialize(pool.address)

    uniV2 = await createContract("MockUniV2Pool")
    await uniV2.initLpToken(tokenA.address, tokenB.address)
    const lpToken = await uniV2.lpToken(tokenA.address, tokenB.address)
    lp = await ethers.getContractAt("MockERC20", lpToken)

    uv2conn = await createContract("UniV2Connector")
  })

  it("addLiquidity", async () => {
    await tokenA.mint(pool.address, toWei("10"))
    await tokenB.mint(pool.address, toWei("10"))

    await lm.addDexSpotConfiguration(100, [0, 1], [1, 1])
    await lm.setDexConnector(
      0,
      uv2conn.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "address", "address"],
        [uniV2.address, lp.address, tokenA.address, tokenB.address]
      )
    )

    await lm.addDexLiquidity(0, [toWei("1"), toWei("1")], 9647270072) // never timeout

    expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("0"))
    expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("0"))
    expect(await tokenA.balanceOf(uniV2.address)).to.equal(toWei("1"))
    expect(await tokenB.balanceOf(uniV2.address)).to.equal(toWei("1"))

    expect(await lp.balanceOf(lm.address)).to.equal(toWei("1"))
    await lm.removeDexLiquidity(0, toWei("0.5"), [toWei("0"), toWei("0")], 9647270072) // never timeout
    expect(await lp.balanceOf(lm.address)).to.equal(toWei("0.5"))

    expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("0"))
    expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("0"))
    expect(await tokenA.balanceOf(uniV2.address)).to.equal(toWei("0.5"))
    expect(await tokenB.balanceOf(uniV2.address)).to.equal(toWei("0.5"))

  })
})
