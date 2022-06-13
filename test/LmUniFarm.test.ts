import { ethers } from "hardhat"
import { expect } from "chai"
import { toWei, toBytes32, createContract, OrderType, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"

const U = ethers.utils
const B = ethers.BigNumber

describe("LmUniFarm", () => {
  let pool: Contract
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
    tokenC = await createContract("MockERC20", ["TokenA", "TokenA", 6])
    tokenD = await createContract("MockERC20", ["TokenB", "TokenB", 6])

    pool = await createContract("MockLiquidityPool")
    // assets
    await pool.setAssetAddress(0, tokenA.address)
    await pool.setAssetAddress(1, tokenB.address)
    await pool.setAssetAddress(2, tokenC.address)
    await pool.setAssetAddress(3, tokenD.address)

    lm = await createContract("LiquidityManager")
    await lm.initialize(vault.address, pool.address)
    dl = await createContract("DexLiquidity", [lm.address])
    await lm.addExternalAccessor(dl.address);
  })


  function makeCallContext1(methodId: string, paramTypes: any, params: any, dexId: number = 0) {
    return {
      methodId: toBytes32(methodId),
      params: paramTypes.length == 0 ? "0x" : U.defaultAbiCoder.encode(paramTypes, params),
      dexId: dexId,
    }
  }


  it("uni-like-2", async () => {
    const univ2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await tokenA.mint(user0.address, toWei("1000"))
    await tokenB.mint(user0.address, toWei("1000"))
    await tokenA.approve(univ2.address, toWei("1000"))
    await tokenB.approve(univ2.address, toWei("1000"))

    await lm.addDexSpotConfiguration(0, 100, [0, 1], [1, 1]) // tokenA/tokenB
    const transferMod = await createContract("TransferModule")
    const univ2Mod = await createContract("UniFarmModule", [
      univ2.address,
      univ2.address,
      tokenA.address,
      tokenB.address,
      0,
      zeroAddress,
    ])
    await lm.installGenericModule(transferMod.address, false);
    await lm.installDexModule(1, univ2Mod.address, false);

    await univ2.addLiquidity(
      tokenA.address,
      tokenB.address,
      toWei("90"),
      toWei("0.9"),
      toWei("90"),
      toWei("0.9"),
      user0.address,
      999999999999,
    )
    expect(await univ2.balanceOf(user0.address)).to.equal(toWei("45.45"))

    const val = await dl.callStatic.getDexValidationData(1, [toWei("10"), toWei("0.1")])
    console.log(val)
    const pval = U.defaultAbiCoder.decode(["uint256", "uint256"], val);
    expect(pval[0]).to.equal(toWei("10"))
    expect(pval[1]).to.equal(toWei("0.1"))

    await dl.addDexLiquidity(1, [toWei("10"), toWei("0.1")], 999999999999, val)
    expect(await dl.callStatic.getDexFees(1)).to.deep.equal([[tokenA.address, tokenB.address], [toWei("0"), toWei("0")], [toWei("0"), toWei("0")]])
    expect(await dl.callStatic.getDexLpBalance(1)).to.equal(toWei("5.05"))

    await univ2.swapA4B(toWei("0.1"))
    await univ2.swapB4A(toWei("0.000999003993018960"))
    var { collectedFeeAmounts, pendingFeeAmounts } = await dl.callStatic.getDexFees(1)
    expect(collectedFeeAmounts[0]).to.be.closeTo(toWei("0"), 10000)
    expect(collectedFeeAmounts[1]).to.be.closeTo(toWei("0"), 10000)
    expect(pendingFeeAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(pendingFeeAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)

    await dl.removeDexLiquidity(
      1,
      await dl.callStatic.getDexLpBalance(1),
      [toWei("0"), toWei("0")],
      999999999999
    )
    expect(await dl.callStatic.getDexLpBalance(1)).to.equal(toWei("0"))
    var { collectedFeeAmounts, pendingFeeAmounts } = await dl.callStatic.getDexFees(1)
    expect(collectedFeeAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(collectedFeeAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)
    expect(pendingFeeAmounts[0]).to.be.closeTo(toWei("0"), 10000)
    expect(pendingFeeAmounts[1]).to.be.closeTo(toWei("0"), 10000)

    await dl.addDexLiquidity(1, [toWei("10"), toWei("0.1")], 999999999999, val)
    await univ2.swapA4B(toWei("0.1"))
    await univ2.swapB4A(toWei("0.000999003993018960"))
    var { collectedFeeAmounts, pendingFeeAmounts } = await dl.callStatic.getDexFees(1)
    expect(collectedFeeAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(collectedFeeAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)
    expect(pendingFeeAmounts[0]).to.be.closeTo(toWei("0.000029970038992498"), 10000)
    expect(pendingFeeAmounts[1]).to.be.closeTo(toWei("0.000000299700389923"), 10000)
  })
})
