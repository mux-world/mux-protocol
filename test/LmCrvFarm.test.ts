import { ethers } from "hardhat"
import { expect } from "chai"
import { toWei, toBytes32, createContract, OrderType, assembleSubAccountId, PositionOrderFlags, sleep, toUnit } from "./deployUtils"
import { Contract, providers } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"

const U = ethers.utils
const B = ethers.BigNumber

describe("LmCrvFarm", () => {
  let pool: Contract
  let tokenA: Contract
  let tokenB: Contract
  let tokenC: Contract
  let tokenD: Contract
  let lm: Contract

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
    await lm.setHandler(user0.address, true)
  })

  it("crv-like-2", async () => {
    const crv = await createContract("Curve2Pool",
      [
        [tokenC.address, tokenD.address],
        1000,
        4000000, //fee 0.04%
        5000000000, // adminFee 0.5
        "USDC-USDT",
        "USDC-USDT",
      ])
    const crv2 = await createContract("Curve2Pool",
      [
        [tokenD.address, tokenC.address],
        1000,
        4000000, //fee 0.04%
        5000000000, // adminFee 0.5
        "USDC-USDT",
        "USDC-USDT",
      ])
    await tokenC.mint(pool.address, toWei("1000"))
    await tokenD.mint(pool.address, toWei("1000"))

    await tokenC.mint(user0.address, toWei("1000"))
    await tokenD.mint(user0.address, toWei("1000"))
    await tokenC.approve(crv.address, toWei("1000"))
    await tokenD.approve(crv.address, toWei("1000"))

    await lm.addDexSpotConfiguration(1, 1, 100, [2, 3], [1, 1]) // uni-like, w100, asset0,1
    const adapter = await createContract("CurveFarm2")

    await expect(lm.setDexWrapper(
      1,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "address", "address", "uint8"],
        [crv2.address, crv2.address, zeroAddress, zeroAddress, 0]
      ))).to.be.revertedWith("!TK")

    await lm.setDexWrapper(
      1,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "address", "address", "uint8"],
        [crv.address, crv.address, zeroAddress, zeroAddress, 0]
      ));

    // const data = await lm.callStatic.getDexLiquidityData(1, [toUnit("100", 6), toUnit("100", 6)]);
    // console.log(data);
    // console.log(await U.defaultAbiCoder.decode(["uint256[]", "uint256", "uint256[]", "uint256"], data)) // 

    await crv.add_liquidity([toUnit("100", 6), toUnit("100", 6)], toWei("200"))
    expect(await crv.balanceOf(user0.address)).to.equal(toWei("200"))

    await lm.addDexLiquidityCurve(1, [toUnit("100", 6), toUnit("100", 6)], 0)
    expect(await lm.callStatic.getDexFees(1)).to.deep.equal([[tokenC.address, tokenD.address], [toWei("0"), toWei("0")], [toWei("0"), toWei("0")]])
    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("200").mul(toWei("0.9996")).div(toWei("1")))

    await lm.removeDexLiquidity(
      1,
      await lm.callStatic.getDexLpBalance(1),
      [toUnit("99", 6), toUnit("99", 6)],
      999999999999
    )
    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("0"))
    await lm.addDexLiquidityCurve(1, [toUnit("100", 6), toUnit("100", 6)], 0)
  })


  it("crv-like-2-farm", async () => {
    const crv = await createContract("Curve2Pool",
      [
        [tokenC.address, tokenD.address],
        1000,
        4000000, //fee 0.04%
        5000000000, // adminFee 0.5
        "USDC-USDT",
        "USDC-USDT",
      ])
    const rewardToken = await createContract("MockERC20", ["RW", "RW", 18])
    const farm = await createContract("DemoCrvMining", [crv.address, rewardToken.address])
    await rewardToken.mint(farm.address, toWei("10000000000"))

    await tokenC.mint(pool.address, toWei("1000"))
    await tokenD.mint(pool.address, toWei("1000"))

    await tokenC.mint(user0.address, toWei("1000"))
    await tokenD.mint(user0.address, toWei("1000"))
    await tokenC.approve(crv.address, toWei("1000"))
    await tokenD.approve(crv.address, toWei("1000"))

    await lm.addDexSpotConfiguration(1, 1, 100, [2, 3], [1, 1]) // uni-like, w100, asset0,1
    const adapter = await createContract("CurveFarm2")

    await lm.setDexWrapper(
      1,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "address", "address", "uint8"],
        [crv.address, crv.address, farm.address, rewardToken.address, 0]
      ));

    await crv.add_liquidity([toUnit("100", 6), toUnit("100", 6)], toWei("200"))
    expect(await crv.balanceOf(user0.address)).to.equal(toWei("200"))

    await lm.addDexLiquidityCurve(1, [toUnit("100", 6), toUnit("100", 6)], 0)
    expect(await lm.callStatic.getDexFees(1)).to.deep.equal([
      [tokenC.address, tokenD.address, rewardToken.address],
      [toWei("0"), toWei("0"), toWei("0")],
      [toWei("0"), toWei("0"), toWei("0")]
    ])
    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("200").mul(toWei("0.9996")).div(toWei("1")))

    await lm.removeDexLiquidity(
      1,
      await lm.callStatic.getDexLpBalance(1),
      [toUnit("99", 6), toUnit("99", 6)],
      999999999999
    )
    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("0"))

  })


  // it("gas", async () => {
  //   const crv = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
  //   await tokenA.mint(pool.address, toWei("1000"))
  //   await tokenB.mint(pool.address, toWei("1000"))

  //   await tokenA.mint(user0.address, toWei("1000"))
  //   await tokenB.mint(user0.address, toWei("1000"))
  //   await tokenA.approve(crv.address, toWei("1000"))
  //   await tokenB.approve(crv.address, toWei("1000"))

  //   await lm.addDexSpotConfiguration(1, 0, 100, [0, 1], [1, 1]) // uni-like, w100, asset0,1
  //   const adapter = await createContract("SushiFarm")
  //   var tx = await lm.setDexWrapper(
  //     1,
  //     adapter.address,
  //     U.defaultAbiCoder.encode(
  //       ["address", "address", "uint256", "address"],
  //       [crv.address, crv.address, 0, zeroAddress]
  //     ));
  //   console.log("setDexWrapper", (await tx.wait()).gasUsed)

  //   await crv.addLiquidity(
  //     tokenA.address,
  //     tokenB.address,
  //     toWei("90"),
  //     toWei("0.9"),
  //     toWei("90"),
  //     toWei("0.9"),
  //     user0.address,
  //     999999999999,
  //   )

  //   const val = await lm.callStatic.getDexValidationData(1, [toWei("10"), toWei("0.1")])
  //   const pval = U.defaultAbiCoder.decode(["uint256", "uint256"], val);
  //   var tx = await lm.addDexLiquidityCurve(1, [toWei("10"), toWei("0.1")], 999999999999, val)
  //   console.log("addDexLiquidityCurve1", (await tx.wait()).gasUsed)

  //   await crv.swapA4B(toWei("0.1"))
  //   await crv.swapB4A(toWei("0.000999003993018960"))

  //   var tx = await lm.removeDexLiquidity(1, await lm.callStatic.getDexLpBalance(1), [toWei("0"), toWei("0")], 999999999999)
  //   console.log("removeDexLiquidity1", (await tx.wait()).gasUsed)

  //   var tx = await lm.claimDexFees(1)
  //   console.log("claimDexFees", (await tx.wait()).gasUsed)

  //   await lm.addDexLiquidityCurve(1, [toWei("10"), toWei("0.1")], 999999999999, val)
  //   console.log("addDexLiquidityCurve2", (await tx.wait()).gasUsed)
  //   await crv.swapA4B(toWei("0.1"))
  //   await crv.swapB4A(toWei("0.000999003993018960"))

  //   var tx = await lm.removeDexLiquidity(1, await lm.callStatic.getDexLpBalance(1), [toWei("0"), toWei("0")], 999999999999)
  //   console.log("removeDexLiquidity2", (await tx.wait()).gasUsed)

  // })
})
