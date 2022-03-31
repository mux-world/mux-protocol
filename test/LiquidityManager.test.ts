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
  let lens: Contract

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

    lens = await createContract("DexLiquidityLens")
  })

  it("getter2", async () => {
    {
      const result = await lm.getAllDexSpotConfiguration()
      expect(result.length).to.equal(0)
    }
    await lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1, 1])
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
  })

  function makeCallContext(methodId: string, paramTypes: any, params: any, dexId: number = 0) {
    return {
      methodId: toBytes32(methodId),
      params: U.defaultAbiCoder.encode(paramTypes, params),
      dexId: dexId,
    }
  }

  it("generic modules", async () => {
    await tokenA.mint(pool.address, toWei("10"))
    await tokenB.mint(pool.address, toWei("10"))

    const transferMod = await createContract("TransferModule")
    let tx = await lm.installModule(transferMod.address);
    await lm.moduleCall(
      makeCallContext(
        "transferFromPool",
        ["uint8[]", "uint256[]"],
        [[0, 1], [toWei("1"), toWei("2")]])
    )
    expect(await tokenA.balanceOf(pool.address)).to.equal(toWei("9"))
    expect(await tokenB.balanceOf(pool.address)).to.equal(toWei("8"))
    expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("1"))
    expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("2"))

    await lm.uninstallModule(toBytes32("transfer-mod"));
    await expect(lm.moduleCall(
      makeCallContext(
        "transferFromPool",
        ["uint8[]", "uint256[]"],
        [[0, 1], [toWei("1"), toWei("2")]])
    )).to.be.revertedWith("MNV") // module not available
  })

  it("dex module", async () => {
    await lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1, 1])
    const mockUniv2 = await createContract("MockUniV2Pool")

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
    await lm.installModule(transferMod.address);
    await lm.installDexModule(1, univ2Mod.address);
    await lm.batchModuleCall(
      [
        makeCallContext(
          "transferFromPool",
          ["uint8[]", "uint256[]"],
          [[0, 1], [toWei("100"), toWei("1")]]),
        makeCallContext(
          "addLiquidity",
          ["uint256[]", "uint256[]", "uint256"],
          [[toWei("100"), toWei("1")], [0, 0], 99999999999],
          1
        ),
      ]
    )

    await lm.addExternalAccessor(lens.address);
    const result = await lens.callStatic.getDexLiquidity(lm.address, 1)
    // console.log(result)
  })

})
