import { ethers } from "hardhat"
import { expect } from "chai"
import { toWei, fromWei, toBytes32, createContract, OrderType, assembleSubAccountId, PositionOrderFlags, toUnit } from "./deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber } from "@ethersproject/bignumber"

const U = ethers.utils
const B = ethers.BigNumber

describe("LiquidityManager", () => {
  let pool: Contract
  let mlp: Contract
  let tokenA: Contract
  let tokenB: Contract
  let tokenC: Contract
  let tokenD: Contract
  let tokenE: Contract
  let lm: Contract
  let dl: Contract

  let user0: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let vault: SignerWithAddress

  let zeroAddress = "0x0000000000000000000000000000000000000000"

  before(async () => {
    const accounts = await ethers.getSigners()
    user0 = accounts[0]
    user1 = accounts[1]
    user2 = accounts[2]
    vault = accounts[3]
  })

  beforeEach(async () => {
    tokenA = await createContract("MockERC20", ["TokenA", "TokenA", 18])
    tokenB = await createContract("MockERC20", ["TokenB", "TokenB", 18])
    tokenC = await createContract("MockERC20", ["TokenA", "TokenA", 18])
    tokenD = await createContract("MockERC20", ["TokenB", "TokenB", 18])
    tokenE = await createContract("MockERC20", ["TokenB", "TokenB", 6])

    mlp = await createContract("MockERC20", ["MLP", "MLP", 18])
    pool = await createContract("MockLiquidityPool")
    // assets
    await pool.setAssetAddress(0, tokenA.address)
    await pool.setAssetAddress(1, tokenB.address)
    await pool.setAssetAddress(2, tokenC.address)
    await pool.setAssetAddress(3, tokenD.address)
    await pool.setAssetAddress(4, tokenE.address)

    lm = await createContract("LiquidityManager")
    await lm.initialize(vault.address, pool.address)
  })

  it("plugin", async () => {
    await tokenA.mint(pool.address, toWei("10"))
    await tokenB.mint(pool.address, toWei("10"))
    await tokenC.mint(pool.address, toWei("10"))

    const testPlugin = await createContract("TestPlugin")
    await lm.setPlugin(testPlugin.address, true)
    await expect(lm.setPlugin(testPlugin.address, true)).to.be.revertedWith("PAE")
    await lm.refreshTokenCache([0, 1, 2])

    expect(await tokenA.balanceOf(user2.address)).to.equal(toWei("0"))
    expect(await tokenB.balanceOf(user2.address)).to.equal(toWei("0"))
    expect(await tokenC.balanceOf(user2.address)).to.equal(toWei("0"))
    //
    const lmp = await ethers.getContractAt("TestPlugin", lm.address)
    await lmp.transfer(user2.address, [0, 1, 2], [toWei("1"), toWei("2"), toWei("3")])
    expect(await tokenA.balanceOf(user2.address)).to.equal(toWei("1"))
    expect(await tokenB.balanceOf(user2.address)).to.equal(toWei("2"))
    expect(await tokenC.balanceOf(user2.address)).to.equal(toWei("3"))

    await lmp.pullAssets([0], [toWei("1")])
    expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("1"))
  })

  it("maintainer", async () => {
    expect(await lm.getMaintainer()).to.equal(zeroAddress)
    await lm.setMaintainer(user1.address)
    expect(await lm.getMaintainer()).to.equal(user1.address)
    await lm.setMaintainer(zeroAddress)
    expect(await lm.getMaintainer()).to.equal(zeroAddress)
  })
})
