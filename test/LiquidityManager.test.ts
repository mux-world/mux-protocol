import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, OrderType, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber } from "@ethersproject/bignumber"
import { Context } from "mocha"
const U = ethers.utils

describe("LiquidityManager", () => {
  let pool: Contract
  let mlp: Contract
  let tokenA: Contract
  let tokenB: Contract
  let tokenC: Contract
  let tokenD: Contract
  let lm: Contract
  let uniV2: Contract
  let uv2conn: Contract
  let curve: Contract
  let curve2conn: Contract

  let user0: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let user3: SignerWithAddress

  let zeroAddress = "0x0000000000000000000000000000000000000000"

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
    await lm.initialize(pool.address)

    uniV2 = await createContract("MockUniV2Pool")
    uv2conn = await createContract("UniV2Connector")

    curve = await createContract("MockCurve2Pool", [tokenB.address, tokenA.address])
    curve2conn = await createContract("Curve2PoolConnector")
  })

  it("getter1", async () => {
    const testConn = await createContract("TestConnector")
    await lm.addDexSpotConfiguration("uniswapV2", 100, [0, 1], [1, 1])
    await lm.setDexConnector(0, testConn.address, "0x")

    expect(await lm.hasConnector(0)).to.equal(true)
    expect(await lm.hasConnector(1)).to.equal(false)
    expect(await lm.hasConnector(111)).to.equal(false)

    await expect(lm.getDexLiquidity(0)).to.be.revertedWith("getLpBalanceCalled")
    await expect(lm.addDexLiquidity(0, [0, 0], 0)).to.be.revertedWith("addDexLiquidityCalled")
    await expect(lm.removeDexLiquidity(0, 1, [0, 0], 0)).to.be.revertedWith("removeDexLiquidityCalled")

    await expect(lm.getDexRewards(0)).to.be.revertedWith("getDexRewardsCalled")
    await expect(lm.getDexFees(0)).to.be.revertedWith("getDexFeesCalled")
    await expect(lm.getDexRedeemableAmounts(0, 1)).to.be.revertedWith("getDexRedeemableAmountsCalled")
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
      expect(result[0].dexId).to.equal(0)
      expect(result[0].dexWeight).to.equal(100)
      expect(result[0].assetIds).deep.equal([0, 1])
      expect(result[0].assetWeightInDex).deep.equal([1, 1])
      expect(await lm.getDexConnector(0)).deep.equal([zeroAddress, 0])
    }
    await lm.addDexSpotConfiguration("uniswapV2", 150, [2, 3], [4, 5])
    {
      const result = await lm.getAllDexSpotConfiguration()
      expect(result.length).to.equal(2)
      expect(result[0].dexId).to.equal(0)
      expect(result[0].dexWeight).to.equal(100)
      expect(result[0].assetIds).deep.equal([0, 1])
      expect(result[0].assetWeightInDex).deep.equal([1, 1])
      expect(result[1].dexId).to.equal(1)
      expect(result[1].dexWeight).to.equal(150)
      expect(result[1].assetIds).deep.equal([2, 3])
      expect(result[1].assetWeightInDex).deep.equal([4, 5])
      expect(await lm.getDexConnector(0)).deep.equal([zeroAddress, 0])
      expect(await lm.getDexConnector(1)).deep.equal([zeroAddress, 0])
    }
    await lm.setDexWeight(0, 30)
    {
      const result = await lm.getAllDexSpotConfiguration()
      expect(result[0].dexWeight).to.equal(30)
    }

    await lm.setDexConnector(
      0,
      uv2conn.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "address", "address", "address", "uint256"],
        [uniV2.address, uniV2.address, tokenA.address, tokenB.address, zeroAddress, 0]
      )
    )
    {
      expect(await lm.getDexConnector(0)).deep.equal([uv2conn.address, 300])
      expect(await lm.getDexConnector(1)).deep.equal([zeroAddress, 0])
    }

    const uniV2_2 = await createContract("MockUniV2Pool")
    await lm.setDexConnector(
      1,
      uv2conn.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "address", "address", "address", "uint256"],
        [uniV2_2.address, uniV2_2.address, tokenC.address, tokenD.address, zeroAddress, 0]
      )
    )
    await lm.setDexSlippage(0, 100)
    {
      expect(await lm.getDexConnector(0)).deep.equal([uv2conn.address, 100])
      expect(await lm.getDexConnector(1)).deep.equal([uv2conn.address, 300])
    }

    await tokenA.mint(pool.address, toWei("10"))
    await tokenB.mint(pool.address, toWei("10"))
    await tokenC.mint(pool.address, toWei("10"))
    await tokenD.mint(pool.address, toWei("10"))

    await lm.addDexLiquidity(0, [toWei("1"), toWei("2")], 9647270072) // never timeout
    await lm.addDexLiquidity(1, [toWei("3"), toWei("4")], 9647270072) // never timeout

    expect(await tokenA.balanceOf(uniV2.address)).to.equal(toWei("1"))
    expect(await tokenB.balanceOf(uniV2.address)).to.equal(toWei("2"))
    expect(await tokenC.balanceOf(uniV2_2.address)).to.equal(toWei("3"))
    expect(await tokenD.balanceOf(uniV2_2.address)).to.equal(toWei("4"))

    expect(await uniV2.balanceOf(lm.address)).to.equal(toWei("1.5"))
    expect(await uniV2_2.balanceOf(lm.address)).to.equal(toWei("3.5"))

    {
      const result = await lm.callStatic.getDexLiquidity(0)
      expect(result.liquidities).deep.equal([toWei("1"), toWei("2")])
      expect(result.lpBalance).to.equal(toWei("1.5"))
    }
    {
      const result = await lm.callStatic.getDexLiquidity(1)
      expect(result.liquidities).deep.equal([toWei("3"), toWei("4")])
      expect(result.lpBalance).to.equal(toWei("3.5"))
    }
  })

  it("connectors", async () => {
    const testConn = await createContract("TestConnector")
    await lm.addDexSpotConfiguration("UniswapV2", 100, [0, 1], [1, 1])
    await lm.setDexConnector(
      0,
      uv2conn.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "address", "address", "address", "uint256"],
        [uniV2.address, uniV2.address, tokenA.address, tokenB.address, zeroAddress, 0]
      )
    )
    await lm.addDexSpotConfiguration("Curve", 200, [1, 0], [1, 1])
    await lm.setDexConnector(
      1,
      curve2conn.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "address", "address", "address", "uint256"],
        [curve.address, curve.address, tokenB.address, tokenA.address, zeroAddress, 0]
      )
    )
  })

  describe("liquidities", async () => {
    beforeEach(async () => {
      await lm.addDexSpotConfiguration("UniswapV2", 100, [0, 1], [1, 1])
      await lm.setDexConnector(
        0,
        uv2conn.address,
        U.defaultAbiCoder.encode(
          ["address", "address", "address", "address", "address", "uint256"],
          [uniV2.address, uniV2.address, tokenA.address, tokenB.address, zeroAddress, 0]
        )
      )
    })

    it("gas", async () => {
      await tokenA.mint(pool.address, toWei("10"))
      await tokenB.mint(pool.address, toWei("10"))

      let tx = await lm.addDexLiquidity(0, [toWei("1"), toWei("1")], 9647270072) // never timeout
      // console.log("addDexLiquidity", (await tx.wait()).gasUsed);
      tx = await lm.getDexRedeemableAmounts(0, toWei("0.1"))
      // console.log("getDexRedeemableAmounts", (await tx.wait()).gasUsed);
      tx = await lm.removeDexLiquidity(0, toWei("0.5"), [toWei("0"), toWei("0")], 9647270072) // never timeout
      // console.log("removeDexLiquidity", (await tx.wait()).gasUsed);
      tx = await lm.getDexFees(0)
      // console.log("getDexFees", (await tx.wait()).gasUsed);
    })

    it("addLiquidity / removeLiquidity", async () => {
      await tokenA.mint(pool.address, toWei("10"))
      await tokenB.mint(pool.address, toWei("10"))

      await lm.addDexLiquidity(0, [toWei("1"), toWei("1")], 9647270072) // never timeout
      expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("0"))
      expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("0"))
      expect(await tokenA.balanceOf(uniV2.address)).to.equal(toWei("1"))
      expect(await tokenB.balanceOf(uniV2.address)).to.equal(toWei("1"))
      {
        const result = await lm.callStatic.getDexRedeemableAmounts(0, toWei("1"))
        expect(result[0]).to.equal(toWei("1"))
        expect(result[1]).to.equal(toWei("1"))
      }
      {
        const result = await lm.callStatic.getDexRedeemableAmounts(0, toWei("0.2"))
        expect(result[0]).to.equal(toWei("0.2"))
        expect(result[1]).to.equal(toWei("0.2"))
      }

      expect(await uniV2.balanceOf(lm.address)).to.equal(toWei("1"))
      await lm.removeDexLiquidity(0, toWei("0.5"), [toWei("0"), toWei("0")], 9647270072) // never timeout
      expect(await uniV2.balanceOf(lm.address)).to.equal(toWei("0.5"))

      expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("0"))
      expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("0"))
      expect(await tokenA.balanceOf(uniV2.address)).to.equal(toWei("0.5"))
      expect(await tokenB.balanceOf(uniV2.address)).to.equal(toWei("0.5"))
      {
        const result = await lm.callStatic.getDexRedeemableAmounts(0, toWei("0.5"))
        expect(result[0]).to.equal(toWei("0.5"))
        expect(result[1]).to.equal(toWei("0.5"))
      }
    })

    it("returnLiquidity", async () => {
      await tokenA.mint(lm.address, toWei("10"))
      await tokenB.mint(lm.address, toWei("10"))

      await lm.returnMuxLiquidity([0], [toWei("3")]) // never timeout
      expect(await tokenA.balanceOf(pool.address)).to.equal(toWei("3"))
      expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("7"))

      await lm.returnMuxLiquidity([0, 1], [toWei("1"), toWei("2")]) // never timeout
      expect(await tokenA.balanceOf(pool.address)).to.equal(toWei("4"))
      expect(await tokenA.balanceOf(lm.address)).to.equal(toWei("6"))
      expect(await tokenB.balanceOf(pool.address)).to.equal(toWei("2"))
      expect(await tokenB.balanceOf(lm.address)).to.equal(toWei("8"))
    })
  })

  it("exceptions", async () => {
    await expect(lm.addDexLiquidity(0, [], 9647270072)).to.be.revertedWith("Mty")
    await expect(lm.addDexLiquidity(0, [toWei("1"), toWei("1")], 9647270072)).to.be.revertedWith("Lst")
    await expect(lm.removeDexLiquidity(0, 1, [], 9647270072)).to.be.revertedWith("Mty")
    await expect(lm.removeDexLiquidity(0, 0, [0, 0], 9647270072)).to.be.revertedWith("A=0")
    await expect(lm.removeDexLiquidity(0, 1, [0, 0], 9647270072)).to.be.revertedWith("Lst")
    await expect(lm.returnMuxLiquidity([], [])).to.be.revertedWith("Mty")
    await expect(lm.returnMuxLiquidity([0, 1], [1])).to.be.revertedWith("Len")
    await expect(lm.returnMuxLiquidity([1], [])).to.be.revertedWith("Len")

    await expect(lm.setDexWeight(0, 100)).to.be.revertedWith("Lst")
    await expect(lm.setDexSlippage(0, 100)).to.be.revertedWith("Lst")

    await lm.addDexSpotConfiguration("UniswapV2", 100, [0, 1], [1, 1])
    await lm.setDexConnector(
      0,
      uv2conn.address,
      U.defaultAbiCoder.encode(
        ["address", "address", "address", "address", "address", "uint256"],
        [uniV2.address, uniV2.address, tokenA.address, tokenB.address, zeroAddress, 0]
      )
    )

    await expect(lm.connect(user2).setDexWeight(0, 100)).to.be.revertedWith("caller is not the owner")
  })
})
