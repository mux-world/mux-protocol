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

  it("getter", async () => {
    {
      const result = await lm.callStatic.getAllDexSpotConfiguration()
      expect(result.length).to.equal(0)
    }

    await expect(lm.getDexSpotConfiguration(0)).to.be.revertedWith("LST")
    await expect(lm.getDexSpotConfiguration(1)).to.be.revertedWith("LST")
    await lm.addDexSpotConfiguration(1, 0, 100, [0, 1], [1, 1])
    await expect(lm.getDexSpotConfiguration(0)).to.be.revertedWith("LST")
    {
      const result = await lm.callStatic.getAllDexSpotConfiguration()
      expect(result.length).to.equal(1)
      expect(result[0].dexId).to.equal(1)
      expect(result[0].dexType).to.equal(0)
      expect(result[0].dexWeight).to.equal(100)
      expect(result[0].assetIds).deep.equal([0, 1])
      expect(result[0].assetWeightInDex).deep.equal([1, 1])
      expect(result[0].totalSpotInDex).deep.equal([B.from(0), B.from(0)])
    }
    await lm.addDexSpotConfiguration(2, 0, 150, [2, 3], [4, 5])
    {
      const result = await lm.callStatic.getAllDexSpotConfiguration()
      expect(result.length).to.equal(2)
      expect(result[0].dexId).to.equal(1)
      expect(result[0].dexWeight).to.equal(100)
      expect(result[0].assetIds).deep.equal([0, 1])
      expect(result[0].assetWeightInDex).deep.equal([1, 1])
      expect(result[1].dexId).to.equal(2)
      expect(result[1].dexWeight).to.equal(150)
      expect(result[1].assetIds).deep.equal([2, 3])
      expect(result[1].assetWeightInDex).deep.equal([4, 5])
    }
    await lm.setDexWeight(1, 30, [10, 20])
    {
      const result = await lm.callStatic.getAllDexSpotConfiguration()
      expect(result[0].dexWeight).to.equal(30)
      expect(result[0].assetWeightInDex).deep.equal([10, 20])
    }

    await lm.addDexSpotConfiguration(3, 1, 100, [0, 1], [1, 1])
    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    const adapter = await createContract("SushiFarm")
    await lm.setDexWrapper(
      3,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "uint256", "address"],
        [mockUniv2.address, mockUniv2.address, 0, zeroAddress]
      ));
    await tokenA.mint(mockUniv2.address, toWei("1000"))
    await tokenB.mint(mockUniv2.address, toWei("2000"))
    var result = await lm.callStatic.getDexSpotConfiguration(3)
    expect(result.dexId).to.equal(3)
    expect(result.dexWeight).to.equal(100)
    expect(result.assetIds).deep.equal([0, 1])
    expect(result.assetWeightInDex).deep.equal([1, 1])
    expect(result.totalSpotInDex).deep.equal([toWei("1000"), toWei("2000")])

    var result = await lm.getDexAdapter(3)
    expect(result.adapter).to.equal(adapter.address)
    expect(result.disabled).to.equal(false)

    // override / upgrade
    const adapter2 = await createContract("SushiFarm")
    await lm.setDexWrapper(
      3,
      adapter2.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "uint256", "address"],
        [mockUniv2.address, mockUniv2.address, 0, zeroAddress]
      ));
    var result = await lm.callStatic.getDexSpotConfiguration(3)
    expect(result.dexId).to.equal(3)
    expect(result.dexWeight).to.equal(100)
    expect(result.assetIds).deep.equal([0, 1])
    expect(result.assetWeightInDex).deep.equal([1, 1])
    expect(result.totalSpotInDex).deep.equal([toWei("1000"), toWei("2000")])

    var result = await lm.getDexAdapter(1)
    expect(result.adapter).to.equal(zeroAddress)
    expect(result.disabled).to.equal(false)

    var result = await lm.getDexAdapter(3)
    expect(result.adapter).to.equal(adapter2.address)
    expect(result.disabled).to.equal(false)

    var result = await lm.getDexAdapterConfig(3)
    result = U.defaultAbiCoder.decode(["address", "address", "uint256", "address"], result)
    expect(result[0]).to.equal(mockUniv2.address)
    expect(result[1]).to.equal(mockUniv2.address)
    expect(result[2]).to.equal(0)
    expect(result[3]).to.equal(zeroAddress)
  })


  it("dex adapter", async () => {
    await lm.addDexSpotConfiguration(1, 0, 100, [0, 1], [1, 1])
    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))
    const adapter = await createContract("SushiFarm")

    await lm.setDexWrapper(
      1,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "uint256", "address"],
        [mockUniv2.address, mockUniv2.address, 0, zeroAddress]
      ));

    expect(await lm.callStatic.getDexLpBalance(1)).to.be.equal(toWei("0"))
    var result = await lm.callStatic.getDexFees(1)
    expect(result.tokens).deep.equal([tokenA.address, tokenB.address])
    expect(result.claimedAmounts).deep.equal([toWei("0"), toWei("0")])
    expect(result.pendingAmounts).deep.equal([toWei("0"), toWei("0")])

    await lm.setHandler(user0.address, true)
    await lm.addDexLiquidityUniSwapV2(1, [toWei("100"), toWei("20")], 9999999999)
    expect(await lm.callStatic.getDexLpBalance(1)).to.be.equal(toWei("60"))
    expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("0"))
    expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("0"))

    var result = await lm.callStatic.getDexFees(1)
    expect(result.tokens).deep.equal([tokenA.address, tokenB.address])
    expect(result.claimedAmounts).deep.equal([toWei("0"), toWei("0")])
    expect(result.pendingAmounts).deep.equal([toWei("0"), toWei("0")])

    await lm.removeDexLiquidity(1, toWei("60"), [toWei("100"), toWei("20")], 9999999999)
    expect(await lm.callStatic.getDexLpBalance(1)).to.be.equal(toWei("0"))
    expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("0"))
    expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("0"))

    await expect(lm.getDexLiquidityData(1, [toWei("100"), toWei("20")])).to.be.revertedWith("SushiFarm::InterfaceUnsupported")

  })

  it("exceptions", async () => {
    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await expect(lm.addDexSpotConfiguration(1, 0, 100, [], [])).to.be.revertedWith("MTY")
    await expect(lm.addDexSpotConfiguration(1, 0, 100, [0, 1], [1])).to.be.revertedWith("LEN")
    await lm.addDexSpotConfiguration(1, 0, 100, [0, 1], [1, 1])
    await expect(lm.setDexWeight(0, 100, [1, 1])).to.be.revertedWith("LST")
    await expect(lm.setDexWeight(2, 100, [1, 1])).to.be.revertedWith("LST")
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

  it("special case", async () => {
    lm = await createContract("TestLiquidityManager")
    await lm.initialize(vault.address, pool.address)

    await lm.addDexSpotConfiguration(1, 0, 100, [0, 1], [1, 1])
    await lm.addDexSpotConfiguration(2, 0, 150, [0, 1], [1, 1])
    await lm.addDexSpotConfiguration(3, 1, 150, [0, 1], [1, 1])

    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))
    const adapter = await createContract("SushiFarm")

    await lm.setDexWrapper(
      1,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "uint256", "address"],
        [mockUniv2.address, mockUniv2.address, 0, zeroAddress]
      ));
    await lm.setDexWrapper(
      2,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "uint256", "address"],
        [mockUniv2.address, mockUniv2.address, 0, zeroAddress]
      ));
    await lm.setDexWrapper(
      3,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "uint256", "address"],
        [mockUniv2.address, mockUniv2.address, 0, zeroAddress]
      ));

    await expect(lm.getDexLpBalance(0)).to.be.revertedWith("ZDI")
    await lm.testContextDexId([1, 2, 3])
    await expect(lm.getDexLpBalanceNested(1, 2)).to.be.revertedWith("NDR")

  })


  it("maintainer", async () => {

    expect(await lm.getMaintainer()).to.equal(zeroAddress)
    await lm.setMaintainer(user1.address)
    expect(await lm.getMaintainer()).to.equal(user1.address)
    await lm.setMaintainer(zeroAddress)
    expect(await lm.getMaintainer()).to.equal(zeroAddress)
  })
})