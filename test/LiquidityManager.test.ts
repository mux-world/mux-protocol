import { ethers } from "hardhat"
import { expect } from "chai"
import { toWei, toBytes32, createContract, OrderType, assembleSubAccountId, PositionOrderFlags, toUnit } from "./deployUtils"
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
    dl = await createContract("DexLiquidity", [lm.address])
  })

  it("getter", async () => {
    {
      const result = await lm.callStatic.getAllDexSpotConfiguration()
      expect(result.length).to.equal(0)
    }

    await expect(lm.getDexSpotConfiguration(0)).to.be.revertedWith("LST")
    await expect(lm.getDexSpotConfiguration(1)).to.be.revertedWith("LST")
    await lm.addDexSpotConfiguration(0, 100, [0, 1], [1, 1])
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
    await lm.addDexSpotConfiguration(0, 150, [2, 3], [4, 5])
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
    await lm.addExternalAccessor(dl.address);
    {
      const result = await dl.callStatic.getAllDexSpotConfiguration()
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

    await lm.addDexSpotConfiguration(1, 100, [4, 0], [2, 2])
    const curve2pool = await createContract("Curve2Pool", [
      [tokenE.address, tokenA.address],
      1000,
      4000000, //fee 0.04%
      5000000000, // adminFee 0.5
      "",
      "",
    ])
    const curveMod = await createContract("Curve2PoolFarmModule", [
      curve2pool.address, tokenE.address, tokenA.address, zeroAddress
    ])
    await tokenE.mint(user0.address, toUnit("1000", 6))
    await tokenE.connect(user0).approve(curve2pool.address, toUnit("1000", 6))
    await tokenA.mint(user0.address, toWei("200"))
    await tokenA.connect(user0).approve(curve2pool.address, toWei("200"))
    await curve2pool.add_liquidity([toUnit("1000", 6), toWei("200")], 0)
    await lm.installDexModule(3, curveMod.address, false)
    {
      console.log(toBytes32("getDynamicWeights"));
      const result = await lm.callStatic.getAllDexSpotConfiguration()
      expect(result[2].dexWeight).to.equal(100)
      expect(result[2].assetWeightInDex).deep.equal([2, 2])
      expect(result[2].totalSpotInDex).deep.equal([toUnit("1000", 6), toWei("200")])
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
    let tx = await lm.installGenericModule(transferMod.address, false);
    console.log(await lm.getModuleInfo(toBytes32("transfer-mod")))

    await lm.callGenericModule(
      toBytes32("transferFromPool"),
      U.defaultAbiCoder.encode(["uint8[]", "uint256[]"], [[0, 1], [toWei("1"), toWei("2")]])
    )
    expect(await tokenA.balanceOf(pool.address)).to.equal(toWei("9"))
    expect(await tokenB.balanceOf(pool.address)).to.equal(toWei("8"))
    expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("1"))
    expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("2"))

    await tokenA.mint(lm.address, toWei("4"))
    await tokenB.mint(lm.address, toWei("5"))
    expect(await tokenA.balanceOf(vault.address)).to.equal(toWei("0"))
    expect(await tokenB.balanceOf(vault.address)).to.equal(toWei("0"))
    await lm.callGenericModule(
      toBytes32("transferToVault"),
      U.defaultAbiCoder.encode(["address[]", "uint256[]"], [[tokenA.address, tokenB.address], [toWei("4"), toWei("5")]]
      )
    )
    expect(await tokenA.balanceOf(vault.address)).to.equal(toWei("4"))
    expect(await tokenB.balanceOf(vault.address)).to.equal(toWei("5"))

    expect(await lm.hasGenericCall(toBytes32("transferFromPool"))).to.be.true;
    await lm.uninstallModule(toBytes32("transfer-mod"));
    expect(await lm.hasGenericCall(toBytes32("transferFromPool"))).to.be.false;
    await expect(lm.callGenericModule(
      toBytes32("transferFromPool"),
      U.defaultAbiCoder.encode(["uint8[]", "uint256[]"], [[0, 1], [toWei("1"), toWei("2")]])
    )).to.be.revertedWith("MNV") // module not available
  })

  it("dex module", async () => {
    await lm.addDexSpotConfiguration(0, 100, [0, 1], [1, 1])
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
    await lm.installGenericModule(transferMod.address, false);
    await lm.installDexModule(1, univ2Mod.address, false);
    await expect(lm.connect(user1).callGenericModule(
      toBytes32("transferFromPool"),
      U.defaultAbiCoder.encode(["uint8[]", "uint256[]"], [[0, 1], [toWei("100"), toWei("1")]])
    )).to.be.revertedWith("FMS")
    await expect(lm.connect(user1).callDexModule(
      1,
      toBytes32("addLiquidity"),
      U.defaultAbiCoder.encode(["uint256[]", "uint256", "bytes"], [[toWei("100"), toWei("1")], 99999999999, "0x"])
    )).to.be.revertedWith("FMS")
    await lm.connect(user0).callGenericModule(
      toBytes32("transferFromPool"),
      U.defaultAbiCoder.encode(["uint8[]", "uint256[]"], [[0, 1], [toWei("100"), toWei("1")]])
    )
    await lm.connect(user0).callDexModule(
      1,
      toBytes32("addLiquidity"),
      U.defaultAbiCoder.encode(["uint256[]", "uint256", "bytes"], [[toWei("100"), toWei("1")], 99999999999, "0x"])
    )

    // console.log(await lm.estimateGas.callDexModule(
    //   1,
    //   toBytes32("getLpBalance"),
    //   "0x"
    // ))
    // console.log(await lm.estimateGas.callDexModule1(
    //   1,
    //   toBytes32("getLpBalance"),
    // ))

    var result = await lm.callStatic.callDexModule(
      1,
      toBytes32("getLpBalance"),
      "0x"
    )
    expect(U.defaultAbiCoder.decode(["uint256"], result)[0]).to.equal(toWei("50.5"))
    var result = await lm.callStatic.callDexModule(
      1,
      toBytes32("getSpotAmounts"),
      result
    )
    expect(U.defaultAbiCoder.decode(["uint256[]"], result)[0]).deep.equal([toWei("100"), toWei("1")])
  })

  it("accessor", async () => {
    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await lm.addDexSpotConfiguration(0, 100, [0, 1], [1, 1])
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
    await lm.installGenericModule(transferMod.address, false);

    var result = await dl.callStatic.getDexLiquidity(1)
    expect(result.liquidities).deep.equal([toWei("0"), toWei("0")])
    expect(result.lpBalance).to.equal(0)

    await lm.installDexModule(1, univ2Mod.address, false);

    var result = await dl.callStatic.getDexLiquidity(1)
    expect(result.liquidities).deep.equal([toWei("0"), toWei("0")])
    expect(result.lpBalance).to.equal(0)

    await dl.addDexLiquidity(1, [toWei("100"), toWei("1")], 99999999999, "0x")
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

    await expect(dl.addDexLiquidity(1, [], 99999999999, "0x")).to.be.revertedWith("MTY")
    await expect(dl.removeDexLiquidity(1, 0, [toWei("100"), toWei("1")], 99999999999)).to.be.revertedWith("A=0")
    await expect(dl.removeDexLiquidity(1, toWei("50.5"), [], 99999999999)).to.be.revertedWith("MTY")
  })


  it("exceptions", async () => {
    const mockUniv2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await expect(lm.addDexSpotConfiguration(0, 100, [], [])).to.be.revertedWith("MTY")
    await expect(lm.addDexSpotConfiguration(0, 100, [0, 1], [1])).to.be.revertedWith("LEN")
    await lm.addDexSpotConfiguration(0, 100, [0, 1], [1, 1])
    await expect(lm.setDexWeight(0, 100, [1, 1])).to.be.revertedWith("LST")
    await expect(lm.setDexWeight(2, 100, [1, 1])).to.be.revertedWith("LST")
    await expect(lm.addDexSpotConfiguration(0, 100, [0, 1], [1])).to.be.revertedWith("LEN")

    const transferMod = await createContract("TransferModule")
    const univ2Mod = await createContract("UniFarmModule", [
      mockUniv2.address,
      mockUniv2.address,
      tokenA.address,
      tokenB.address,
      0,
      zeroAddress,
    ])
    await expect(lm.installGenericModule(user0.address, false)).to.be.revertedWith("MNC")
    await expect(lm.installGenericModule(lm.address, false)).to.be.revertedWith("IVI")
    await lm.installGenericModule(transferMod.address, false)
    await expect(lm.installGenericModule(transferMod.address, false)).to.be.revertedWith("MHI")

    const mockCrv = await createContract("MockCurve2Pool", [tokenA.address, tokenB.address])

    const crvMod = await createContract("Curve2PoolFarmModule", [
      mockCrv.address,
      tokenA.address,
      tokenB.address,
      mockCrv.address,
    ])

    await lm.installDexModule(1, univ2Mod.address, false);
    await expect(lm.installDexModule(1, crvMod.address, false)).to.revertedWith("MLR")

    await expect(dl.addDexLiquidity(1, [toWei("100"), toWei("1")], 99999999999, "0x")).to.be.revertedWith("FMS")
    await lm.addExternalAccessor(dl.address);
    await expect(lm.addExternalAccessor(dl.address)).to.be.revertedWith("DEA")
    await dl.addDexLiquidity(1, [toWei("100"), toWei("1")], 99999999999, "0x");

    await lm.removeExternalAccessor(dl.address);
    await expect(lm.removeExternalAccessor(dl.address)).to.be.revertedWith("ANE")
    await expect(dl.addDexLiquidity(1, [toWei("100"), toWei("1")], 99999999999, "0x")).to.be.revertedWith("FMS")
  })

})
