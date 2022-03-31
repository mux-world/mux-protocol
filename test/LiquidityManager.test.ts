import { ethers } from "hardhat"
import { expect } from "chai"
import { toWei, toBytes32, createContract, OrderType, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber } from "@ethersproject/bignumber"

const U = ethers.utils

describe("LiquidityManager", () => {
  let pool: Contract
  let mlp: Contract
  let tokenA: Contract
  let tokenB: Contract
  let tokenC: Contract
  let tokenD: Contract
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

    mlp = await createContract("MockERC20", ["MLP", "MLP", 18])
    pool = await createContract("MockLiquidityPool")
    // assets
    await pool.setAssetAddress(0, tokenA.address)
    await pool.setAssetAddress(1, tokenB.address)
    await pool.setAssetAddress(2, tokenC.address)
    await pool.setAssetAddress(3, tokenD.address)

    lm = await createContract("LiquidityManager")
    await lm.initialize(vault.address, pool.address)
    dl = await createContract("DexLiquidity", [lm.address])
  })

  it("getter", async () => {
    {
      const result = await lm.getAllDexSpotConfiguration()
      expect(result.length).to.equal(0)
    }

    await expect(lm.getDexSpotConfiguration(0)).to.be.revertedWith("LST")
    await expect(lm.getDexSpotConfiguration(1)).to.be.revertedWith("LST")
    await lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1, 1])
    await expect(lm.getDexSpotConfiguration(0)).to.be.revertedWith("LST")
    {
      const result = await lm.getAllDexSpotConfiguration()
      expect(result.length).to.equal(1)
      expect(result[0].dexId).to.equal(1)
      expect(result[0].dexWeight).to.equal(100)
      expect(result[0].assetIds).deep.equal([0, 1])
      expect(result[0].assetWeightInDex).deep.equal([1, 1])
    }
    await lm.addDexSpotConfiguration("uniswapV2", 150, [2, 3], [4, 5])
    {
      const result = await lm.getAllDexSpotConfiguration()
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
      const result = await lm.getAllDexSpotConfiguration()
      expect(result[0].dexWeight).to.equal(30)
      expect(result[0].assetWeightInDex).deep.equal([10, 20])
    }
    await lm.addExternalAccessor(dl.address);
    {
      const result = await dl.getAllDexSpotConfiguration()
      expect(result.length).to.equal(2)
      expect(result[0].dexId).to.equal(1)
      expect(result[0].dexWeight).to.equal(30)
      expect(result[0].assetIds).deep.equal([0, 1])
      expect(result[0].assetWeightInDex).deep.equal([10, 20])
      expect(result[1].dexId).to.equal(2)
      expect(result[1].dexWeight).to.equal(150)
      expect(result[1].assetIds).deep.equal([2, 3])
      expect(result[1].assetWeightInDex).deep.equal([4, 5])
    }
  })

  function makeCallContext1(methodId: string, paramTypes: any, params: any, dexId: number = 0) {
    return {
      methodId: toBytes32(methodId),
      params: paramTypes.length == 0 ? "0x" : U.defaultAbiCoder.encode(paramTypes, params),
      dexId: dexId,
    }
  }

  function makeCallContext2(methodId: string, params: any, dexId: number = 0) {
    return {
      methodId: toBytes32(methodId),
      params: params,
      dexId: dexId,
    }
  }

  it("generic modules", async () => {
    await tokenA.mint(pool.address, toWei("10"))
    await tokenB.mint(pool.address, toWei("10"))

    const transferMod = await createContract("TransferModule")
    let tx = await lm.installGenericModule(transferMod.address);
    console.log(await lm.getModuleInfo(toBytes32("transfer-mod")))

    await lm.moduleCall(
      makeCallContext1(
        "transferFromPool",
        ["uint8[]", "uint256[]"],
        [[0, 1], [toWei("1"), toWei("2")]])
    )
    expect(await tokenA.balanceOf(pool.address)).to.equal(toWei("9"))
    expect(await tokenB.balanceOf(pool.address)).to.equal(toWei("8"))
    expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("1"))
    expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("2"))

    await tokenA.mint(lm.address, toWei("4"))
    await tokenB.mint(lm.address, toWei("5"))
    expect(await tokenA.balanceOf(vault.address)).to.equal(toWei("0"))
    expect(await tokenB.balanceOf(vault.address)).to.equal(toWei("0"))
    await lm.moduleCall(
      makeCallContext1(
        "transferToVault",
        ["address[]", "uint256[]"],
        [[tokenA.address, tokenB.address], [toWei("4"), toWei("5")]])
    )
    expect(await tokenA.balanceOf(vault.address)).to.equal(toWei("4"))
    expect(await tokenB.balanceOf(vault.address)).to.equal(toWei("5"))

    expect(await lm.hasGenericCall(toBytes32("transferFromPool"))).to.be.true;
    await lm.uninstallModule(toBytes32("transfer-mod"));
    expect(await lm.hasGenericCall(toBytes32("transferFromPool"))).to.be.false;
    await expect(lm.moduleCall(
      makeCallContext1(
        "transferFromPool",
        ["uint8[]", "uint256[]"],
        [[0, 1], [toWei("1"), toWei("2")]])
    )).to.be.revertedWith("MNV") // module not available
  })

  it("dex module", async () => {
    await lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1, 1])
    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])

    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    const transferMod = await createContract("TransferModule")
    const univ2Mod = await createContract("UniFarmModule", [
      mockUniv2.address,
      mockUniv2.address,
      tokenA.address,
      tokenB.address,
      0,
      zeroAddress,
    ])
    await lm.installGenericModule(transferMod.address);
    await lm.installDexModule(1, univ2Mod.address);

    await expect(lm.batchModuleCall([])).to.be.revertedWith("MTY")
    await expect(lm.connect(user1).batchModuleCall(
      [
        makeCallContext1(
          "transferFromPool",
          ["uint8[]", "uint256[]"],
          [[0, 1], [toWei("100"), toWei("1")]]),
        makeCallContext1(
          "addLiquidity",
          ["uint256[]", "uint256[]", "uint256"],
          [[toWei("100"), toWei("1")], [0, 0], 99999999999],
          1
        ),
      ]
    )).to.be.revertedWith("FMS")
    await lm.batchModuleCall(
      [
        makeCallContext1(
          "transferFromPool",
          ["uint8[]", "uint256[]"],
          [[0, 1], [toWei("100"), toWei("1")]]),
        makeCallContext1(
          "addLiquidity",
          ["uint256[]", "uint256[]", "uint256"],
          [[toWei("100"), toWei("1")], [0, 0], 99999999999],
          1
        ),
      ]
    )
    var result = await lm.callStatic.moduleCall(
      makeCallContext1("getLpBalance", [], [], 1)
    )
    expect(U.defaultAbiCoder.decode(["uint256"], result)[0]).to.equal(toWei("50.5"))
    var result = await lm.callStatic.moduleCall(
      makeCallContext2("getSpotAmounts", result, 1)
    )
    expect(U.defaultAbiCoder.decode(["uint256[]"], result)[0]).deep.equal([toWei("100"), toWei("1")])
  })

  it("accessor", async () => {
    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1, 1])
    await lm.addExternalAccessor(dl.address);

    const transferMod = await createContract("TransferModule")
    const univ2Mod = await createContract("UniFarmModule", [
      mockUniv2.address,
      mockUniv2.address,
      tokenA.address,
      tokenB.address,
      0,
      zeroAddress,
    ])
    await lm.installGenericModule(transferMod.address);

    var result = await dl.callStatic.getDexLiquidity(1)
    expect(result.liquidities).deep.equal([toWei("0"), toWei("0")])
    expect(result.lpBalance).to.equal(0)

    await lm.installDexModule(1, univ2Mod.address);

    var result = await dl.callStatic.getDexLiquidity(1)
    expect(result.liquidities).deep.equal([toWei("0"), toWei("0")])
    expect(result.lpBalance).to.equal(0)

    await dl.addDexLiquidity(1, [toWei("100"), toWei("1")], 99999999999)
    var result = await dl.callStatic.getDexLiquidity(1)
    expect(result.liquidities).deep.equal([toWei("100"), toWei("1")])
    expect(result.lpBalance).to.equal(toWei("50.5"))

    expect(await tokenA.balanceOf(pool.address)).to.equal(toWei("900"))
    expect(await tokenB.balanceOf(pool.address)).to.equal(toWei("999"))

    await dl.removeDexLiquidity(1, toWei("50.5"), [toWei("100"), toWei("1")], 99999999999)
    var result = await dl.callStatic.getDexLiquidity(1)
    expect(result.liquidities).deep.equal([toWei("0"), toWei("0")])
    expect(result.lpBalance).to.equal(0)

    expect(await tokenA.balanceOf(pool.address)).to.equal(toWei("1000"))
    expect(await tokenB.balanceOf(pool.address)).to.equal(toWei("1000"))

    await expect(dl.addDexLiquidity(1, [], 99999999999)).to.be.revertedWith("MTY")
    await expect(dl.removeDexLiquidity(1, 0, [toWei("100"), toWei("1")], 99999999999)).to.be.revertedWith("A=0")
    await expect(dl.removeDexLiquidity(1, toWei("50.5"), [], 99999999999)).to.be.revertedWith("MTY")
  })

  it("accessor2", async () => {
    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1, 1])
    await lm.addExternalAccessor(dl.address);

    const transferMod = await createContract("TransferModule")
    const univ2Mod = await createContract("UniFarmModule", [
      mockUniv2.address,
      mockUniv2.address,
      tokenA.address,
      tokenB.address,
      0,
      zeroAddress,
    ])
    await lm.installGenericModule(transferMod.address);
    await lm.installDexModule(1, univ2Mod.address);
    await dl.addDexLiquidity(1, [toWei("100"), toWei("1")], 99999999999)

    await tokenA.mint(user0.address, toWei("1000"))
    await tokenB.mint(user0.address, toWei("1000"))
    await tokenA.approve(mockUniv2.address, toWei("10000"))
    await tokenB.approve(mockUniv2.address, toWei("10000"))

    await mockUniv2.swapA4B(toWei("0.1"))
    console.log(await mockUniv2.getPrice())
    console.log(await tokenB.balanceOf(user0.address))

    await mockUniv2.swapB4A(toWei("0.000999003993018960"))
    console.log(await mockUniv2.getPrice())

    var result = U.defaultAbiCoder.decode(
      ["uint256[]"],
      await lm.callStatic.moduleCall(makeCallContext2("getFees", "0x", 1))
    )
    console.log(result)
    // await dl.removeDexLiquidity(1, toWei("50.5"), [toWei("100"), toWei("1")], 99999999999)
  })

  it("exceptions", async () => {
    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await expect(lm.addDexSpotConfiguration("uniswapV2", 100, [], [])).to.be.revertedWith("MTY")
    await expect(lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1])).to.be.revertedWith("LEN")
    await lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1, 1])
    await expect(lm.setDexWeight(0, 100, [1, 1])).to.be.revertedWith("LST")
    await expect(lm.setDexWeight(2, 100, [1, 1])).to.be.revertedWith("LST")
    await expect(lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1])).to.be.revertedWith("LEN")

    const transferMod = await createContract("TransferModule")
    const univ2Mod = await createContract("UniFarmModule", [
      mockUniv2.address,
      mockUniv2.address,
      tokenA.address,
      tokenB.address,
      0,
      zeroAddress,
    ])
    await expect(lm.installGenericModule(user0.address)).to.be.revertedWith("MNC")
    await expect(lm.installGenericModule(lm.address)).to.be.revertedWith("IMM")
    await lm.installGenericModule(transferMod.address)
    await expect(lm.installGenericModule(transferMod.address)).to.be.revertedWith("MHI")

    const crvMod = await createContract("CurveFarmModule", [
      mockUniv2.address,
      tokenA.address,
      tokenB.address,
      mockUniv2.address,
    ])

    await lm.installDexModule(1, univ2Mod.address);
    await expect(lm.installDexModule(1, crvMod.address)).to.revertedWith("MLR")

    await expect(dl.addDexLiquidity(1, [toWei("100"), toWei("1")], 99999999999)).to.be.revertedWith("FMS")
    await lm.addExternalAccessor(dl.address);
    await expect(lm.addExternalAccessor(dl.address)).to.be.revertedWith("DEA")
    await dl.addDexLiquidity(1, [toWei("100"), toWei("1")], 99999999999);

    await lm.removeExternalAccessor(dl.address);
    await expect(lm.removeExternalAccessor(dl.address)).to.be.revertedWith("ANE")
    await expect(dl.addDexLiquidity(1, [toWei("100"), toWei("1")], 99999999999)).to.be.revertedWith("FMS")
  })
})
