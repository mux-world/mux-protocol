import { ethers } from "hardhat"
import { expect } from "chai"
import { toWei, toBytes32, createContract, OrderType, assembleSubAccountId, PositionOrderFlags, sleep, toUnit } from "./deployUtils"
import { Contract, providers } from "ethers"
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

  it("uni-like-2", async () => {
    const univ2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await tokenA.mint(user0.address, toWei("1000"))
    await tokenB.mint(user0.address, toWei("1000"))
    await tokenA.approve(univ2.address, toWei("1000"))
    await tokenB.approve(univ2.address, toWei("1000"))

    await lm.addDexSpotConfiguration(1, 0, 100, [0, 1], [1, 1]) // uni-like, w100, asset0,1
    const adapter = await createContract("SushiFarm")
    await lm.setDexWrapper(
      1,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "uint256", "address"],
        [univ2.address, univ2.address, 0, zeroAddress]
      ));

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

    await lm.addDexLiquidityUniSwapV2(1, [toWei("10"), toWei("0.1")], 999999999999)
    expect(await lm.callStatic.getDexFees(1)).to.deep.equal([[tokenA.address, tokenB.address], [toWei("0"), toWei("0")], [toWei("0"), toWei("0")]])
    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("5.05"))

    await univ2.swapA4B(toWei("0.1"))
    await univ2.swapB4A(toWei("0.000999003993018960"))
    var { claimedAmounts, pendingAmounts } = await lm.callStatic.getDexFees(1)
    expect(claimedAmounts[0]).to.be.closeTo(toWei("0"), 10000)
    expect(claimedAmounts[1]).to.be.closeTo(toWei("0"), 10000)
    expect(pendingAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(pendingAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)
    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("5.049984865134865134"))

    await lm.removeDexLiquidity(
      1,
      await lm.callStatic.getDexLpBalance(1),
      [toWei("0"), toWei("0")],
      999999999999
    )
    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("0"))
    var { claimedAmounts, pendingAmounts } = await lm.callStatic.getDexFees(1)
    expect(claimedAmounts[0]).to.be.closeTo(toWei("0"), 10000)
    expect(claimedAmounts[1]).to.be.closeTo(toWei("0"), 10000)
    expect(pendingAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(pendingAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)

    await lm.claimDexFees(1)
    var { claimedAmounts, pendingAmounts } = await lm.callStatic.getDexFees(1)
    expect(claimedAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(claimedAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)
    expect(pendingAmounts[0]).to.be.closeTo(toWei("0"), 10000)
    expect(pendingAmounts[1]).to.be.closeTo(toWei("0"), 10000)

    expect(await tokenA.balanceOf(vault.address)).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(await tokenB.balanceOf(vault.address)).to.be.closeTo(toWei("0.000000299701197905"), 10000)

    await lm.addDexLiquidityUniSwapV2(1, [toWei("10"), toWei("0.1")], 999999999999)
    await univ2.swapA4B(toWei("0.1"))
    await univ2.swapB4A(toWei("0.000999003993018960"))
    var { claimedAmounts, pendingAmounts } = await lm.callStatic.getDexFees(1)
    expect(claimedAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(claimedAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)
    expect(pendingAmounts[0]).to.be.closeTo(toWei("0.000029970038992498"), 10000)
    expect(pendingAmounts[1]).to.be.closeTo(toWei("0.000000299700389923"), 10000)

    await expect(lm.addDexLiquidityCurve(1, [toWei("10"), toWei("0.1")], toWei("0"))).to.be.revertedWith("SushiFarm::InterfaceUnsupported")
  })


  it("uni-like-2-farm", async () => {
    const univ2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    const farm = await createContract("DemoLpMining")

    var blockTime = (await ethers.provider.getBlock("latest")).timestamp
    await farm.initialize(toWei("1"), blockTime)
    await farm.add(toWei("20000"), univ2.address)

    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await tokenA.mint(user0.address, toWei("1000"))
    await tokenB.mint(user0.address, toWei("1000"))
    await tokenA.approve(univ2.address, toWei("1000"))
    await tokenB.approve(univ2.address, toWei("1000"))

    await lm.addDexSpotConfiguration(1, 0, 100, [0, 1], [1, 1]) // uni-like, w100, asset0,1
    const adapter = await createContract("SushiFarm")
    await lm.setDexWrapper(
      1,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "uint256", "address"],
        [univ2.address, univ2.address, 0, farm.address]
      ));

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
    await lm.addDexLiquidityUniSwapV2(1, [toWei("10"), toWei("0.1")], 999999999999)
    var begin = (await ethers.provider.getBlock("latest")).timestamp
    expect(await lm.callStatic.getDexFees(1)).to.deep.equal([
      [tokenA.address, tokenB.address, await farm.rewardToken()],
      [toWei("0"), toWei("0"), toWei("0")],
      [toWei("0"), toWei("0"), toWei("0")]
    ])

    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("5.05"))

    await univ2.swapA4B(toWei("0.1"))
    await univ2.swapB4A(toWei("0.000999003993018960"))

    await sleep(5000)
    var end = (await ethers.provider.getBlock("latest")).timestamp

    var { claimedAmounts, pendingAmounts } = await lm.callStatic.getDexFees(1)
    expect(claimedAmounts[0]).to.be.closeTo(toWei("0"), 10000)
    expect(claimedAmounts[1]).to.be.closeTo(toWei("0"), 10000)
    expect(pendingAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(pendingAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)
    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("5.049984865134865134"))
    expect(pendingAmounts[2]).to.be.closeTo(toWei("1").mul(B.from(end - begin)), toUnit("1", 9))

    await lm.removeDexLiquidity(
      1,
      await lm.callStatic.getDexLpBalance(1),
      [toWei("0"), toWei("0")],
      999999999999
    )
    var end = (await ethers.provider.getBlock("latest")).timestamp
    expect(await lm.callStatic.getDexLpBalance(1)).to.equal(toWei("0"))
    var { claimedAmounts, pendingAmounts } = await lm.callStatic.getDexFees(1)
    expect(claimedAmounts[0]).to.be.closeTo(toWei("0"), 10000)
    expect(claimedAmounts[1]).to.be.closeTo(toWei("0"), 10000)
    expect(claimedAmounts[2]).to.be.closeTo(toWei("1").mul(B.from(end - begin)), toUnit("1", 9))
    expect(pendingAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(pendingAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)

    await lm.claimDexFees(1)
    var { claimedAmounts, pendingAmounts } = await lm.callStatic.getDexFees(1)
    expect(claimedAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(claimedAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)
    expect(pendingAmounts[0]).to.be.closeTo(toWei("0"), 10000)
    expect(pendingAmounts[1]).to.be.closeTo(toWei("0"), 10000)
    expect(pendingAmounts[2]).to.be.closeTo(toWei("0"), 10000)

    await lm.addDexLiquidityUniSwapV2(1, [toWei("10"), toWei("0.1")], 999999999999)
    await univ2.swapA4B(toWei("0.1"))
    await univ2.swapB4A(toWei("0.000999003993018960"))
    var { claimedAmounts, pendingAmounts } = await lm.callStatic.getDexFees(1)
    expect(claimedAmounts[0]).to.be.closeTo(toWei("0.000029970119790568"), 10000)
    expect(claimedAmounts[1]).to.be.closeTo(toWei("0.000000299701197905"), 10000)
    expect(pendingAmounts[0]).to.be.closeTo(toWei("0.000029970038992498"), 10000)
    expect(pendingAmounts[1]).to.be.closeTo(toWei("0.000000299700389923"), 10000)

  })

  it("gas", async () => {
    const univ2 = await createContract("MockUniV2Pool", [tokenA.address, tokenB.address])
    await tokenA.mint(pool.address, toWei("1000"))
    await tokenB.mint(pool.address, toWei("1000"))

    await tokenA.mint(user0.address, toWei("1000"))
    await tokenB.mint(user0.address, toWei("1000"))
    await tokenA.approve(univ2.address, toWei("1000"))
    await tokenB.approve(univ2.address, toWei("1000"))

    await lm.addDexSpotConfiguration(1, 0, 100, [0, 1], [1, 1]) // uni-like, w100, asset0,1
    const adapter = await createContract("SushiFarm")
    var tx = await lm.setDexWrapper(
      1,
      adapter.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "uint256", "address"],
        [univ2.address, univ2.address, 0, zeroAddress]
      ));
    console.log("setDexWrapper", (await tx.wait()).gasUsed)

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

    var tx = await lm.addDexLiquidityUniSwapV2(1, [toWei("10"), toWei("0.1")], 999999999999)
    console.log("addDexLiquidityUniSwapV21", (await tx.wait()).gasUsed)

    await univ2.swapA4B(toWei("0.1"))
    await univ2.swapB4A(toWei("0.000999003993018960"))

    var tx = await lm.removeDexLiquidity(1, await lm.callStatic.getDexLpBalance(1), [toWei("0"), toWei("0")], 999999999999)
    console.log("removeDexLiquidity1", (await tx.wait()).gasUsed)

    var tx = await lm.claimDexFees(1)
    console.log("claimDexFees", (await tx.wait()).gasUsed)

    await lm.addDexLiquidityUniSwapV2(1, [toWei("10"), toWei("0.1")], 999999999999)
    console.log("addDexLiquidityUniSwapV22", (await tx.wait()).gasUsed)
    await univ2.swapA4B(toWei("0.1"))
    await univ2.swapB4A(toWei("0.000999003993018960"))

    var tx = await lm.removeDexLiquidity(1, await lm.callStatic.getDexLpBalance(1), [toWei("0"), toWei("0")], 999999999999)
    console.log("removeDexLiquidity2", (await tx.wait()).gasUsed)

  })
})
