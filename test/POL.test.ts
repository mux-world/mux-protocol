import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, rate, PreMinedTokenTotalSupply, createFactory } from "./deployUtils"
import { createContract, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { MlpToken, TestOrderBook, TestLiquidityPool, LiquidityManager, Reader, POL, WETH9 } from "../typechain"
const U = ethers.utils

describe("POL", () => {
  let mlp: MlpToken
  let pool: TestLiquidityPool
  let orderBook: TestOrderBook
  let liquidityManager: LiquidityManager
  let nativeUnwrapper: Contract
  let weth9: WETH9
  let reader: Reader
  let pol: POL

  let op: SignerWithAddress
  let broker: SignerWithAddress
  let vault: SignerWithAddress

  before(async () => {
    const accounts = await ethers.getSigners()
    op = accounts[1]
    broker = accounts[2]
    vault = accounts[3]
  })

  beforeEach(async () => {
    const libLiquidity = await createContract("LibLiquidity")
    const poolHop1 = await createContract("TestLiquidityPoolHop1")
    const poolHop2 = await createContract("TestLiquidityPoolHop2", [], { "contracts/libraries/LibLiquidity.sol:LibLiquidity": libLiquidity })
    pool = await ethers.getContractAt("TestLiquidityPool", poolHop1.address)
    mlp = (await createContract("MlpToken")) as MlpToken
    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("TestOrderBook", [], { "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook })) as TestOrderBook
    liquidityManager = (await createContract("LiquidityManager")) as LiquidityManager
    weth9 = (await createContract("WETH9")) as WETH9
    nativeUnwrapper = await createContract("NativeUnwrapper", [weth9.address])
    pol = (await createContract("POL")) as POL
    await mlp.initialize("MLP", "MLP")
    await orderBook.initialize(pool.address, mlp.address, weth9.address, nativeUnwrapper.address)
    await orderBook.addBroker(broker.address)
    await orderBook.setLiquidityLockPeriod(5 * 60)
    await orderBook.setOrderTimeout(300, 86400 * 365)
    await liquidityManager.initialize(vault.address, pool.address)
    await pool.initialize(poolHop2.address, mlp.address, orderBook.address, weth9.address, nativeUnwrapper.address, vault.address)
    // fundingInterval, liqBase, liqDyn, σ_strict, brokerGas
    await pool.setNumbers(3600 * 8, rate("0.0001"), rate("0.0000"), rate("0.01"), toWei("0"))
    // mlpPrice, mlpPrice
    await pool.setEmergencyNumbers(toWei("1"), toWei("2000"))
    await pool.setLiquidityManager(liquidityManager.address, true)
    await mlp.transfer(pool.address, toWei(PreMinedTokenTotalSupply))
    await pol.connect(op).initialize(pool.address, orderBook.address, weth9.address)

    const muxWeth = await createContract("MuxToken")
    await muxWeth.initialize("muxWeth", "muxWeth")
    await muxWeth.transfer(pool.address, toWei(PreMinedTokenTotalSupply))

    // 0 = ETH
    // id, symbol, decimals, stable, token, mux
    await pool.addAsset(0, toBytes32("ETH"), 18, false, weth9.address, muxWeth.address)
    // id, symbol, imr, mmr, fee, fee, minBps, minTime, spotWeight
    await pool.setAssetParams(0, toBytes32("ETH"), rate("0.1"), rate("0.05"), rate("0.001"), rate("0.001"), rate("0.01"), 10, 2)
    // id, tradable, openable, shortable, useStable, enabled, strict, liq, halfSpread, maxLong, maxShort
    await pool.setAssetFlags(0, true, true, true, false, true, false, true, rate("0"), toWei("10000000"), toWei("10000000"))
    await pool.setFundingParams(0, rate("0.0003"), rate("0.0009"))

    await pool.setBlockTimestamp(86400 * 1)
    await orderBook.setBlockTimestamp(86400 * 1)
  })

  it("buyMUXLP and withdraw", async () => {
    // distributor will transfer WETH into POL
    await weth9.deposit({ value: toWei("1") })
    await weth9.transfer(pol.address, toWei("1"))
    // buy
    {
      await expect(pol.buyMUXLP(0, toWei("1"))).to.revertedWith("must be maintainer or owner")
      await expect(pol.connect(op).buyMUXLP(0, toWei("1")))
        .to.emit(orderBook, "NewLiquidityOrder")
        .withArgs(pol.address, 0, 0, toWei("1"), true)
      expect(await weth9.balanceOf(pol.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("1"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pol.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1000000000000000000"))
    }
    {
      const current = toWei("29700")
      const target = toWei("29700")
      await pool.setBlockTimestamp(86400 * 2 + 330)
      await orderBook.setBlockTimestamp(86400 * 2 + 330)
      await orderBook.connect(broker).fillLiquidityOrder(0, toWei("1000"), toWei("1000"), current, target)
      expect(await weth9.balanceOf(pol.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await weth9.balanceOf(pool.address)).to.equal(toWei("1"))
      expect(await mlp.balanceOf(pol.address)).to.equal(toWei("0.9999")) // (1 - fee) * 1000 / 1000
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("999999999999999999.0001"))
      const collateralInfo = await pool.getAssetInfo(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1")) // fee = 0.01
      expect(collateralInfo.collectedFee).to.equal(toWei("0.0001"))
    }
    // withdraw
    await expect(pol.transferAllERC20(op.address, [mlp.address])).to.revertedWith("Ownable: caller is not the owner")
    await pol.connect(op).transferAllERC20(op.address, [mlp.address])
    expect(await mlp.balanceOf(pol.address)).to.equal(toWei("0"))
    expect(await mlp.balanceOf(op.address)).to.equal(toWei("0.9999"))
  })
})
