import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, createFactory, ensureFinished } from "./deployUtils"
import { createContract, assembleSubAccountId } from "./deployUtils"
import { MlpToken, TestOrderBook, TestLiquidityPool, WBNB, NativeUnwrapper } from "../typechain"
const U = ethers.utils

describe("BscCompatible - this test should be tested on bscTestnet", () => {
  let wbnb: WBNB
  let pool: TestLiquidityPool
  let orderBook: TestOrderBook

  let trader1: SignerWithAddress
  let lp1: SignerWithAddress
  let broker: SignerWithAddress
  let vault: SignerWithAddress

  before(async () => {
    const accounts = await ethers.getSigners()
    if (accounts.length < 3) {
      throw new Error("BscCompatible test requires 3 addresses")
    }
    vault = accounts[0]
    trader1 = accounts[0]
    lp1 = accounts[1]
    broker = accounts[2]
  })

  beforeEach(async () => {
    wbnb = (await createContract("WBNB")) as WBNB
    const nativeUnwrapper = await createContract("NativeUnwrapper", [wbnb.address, { gasLimit: 1000000 }])
    const poolHop1 = await createContract("TestLiquidityPoolHop1")
    const poolHop2 = await createContract("TestLiquidityPoolHop2")
    const poolProxy = await createContract("TransparentUpgradeableProxy", [poolHop1.address, lp1.address /* admin */, "0x", { gasLimit: 1000000 }])
    orderBook = (await createContract("TestOrderBook")) as TestOrderBook
    console.log("bscTestnet wbnb", wbnb.address, "pool", poolProxy.address, "book", orderBook.address, "unwrap", nativeUnwrapper.address)
    console.log("bscTestnet contracts deployed")
    pool = (await createFactory("TestLiquidityPool")).attach(poolProxy.address)
    const mlp = "0x0000000000000000000000000000000000000000"
    await ensureFinished(orderBook.initialize(pool.address, mlp, wbnb.address, nativeUnwrapper.address))
    await ensureFinished(orderBook.addBroker(broker.address))
    await ensureFinished(
      pool.initialize(poolHop2.address, mlp, orderBook.address, broker.address /* test only */, wbnb.address, nativeUnwrapper.address, vault.address)
    )
    await ensureFinished(nativeUnwrapper.addWhiteList(pool.address))
    await ensureFinished(nativeUnwrapper.addWhiteList(orderBook.address))
    console.log("bscTestnet contracts initialized")

    // 0 = BNB
    // id, symbol, decimals, stable, token, mux
    await ensureFinished(pool.addAsset(0, toBytes32("BNB"), 18, false, wbnb.address, wbnb.address))
    // id, tradable, openable, shortable, useStable, enabled, strict
    await ensureFinished(pool.setAssetFlags(0, true, true, true, false, true, false))
    console.log("bscTestnet added assets")
  })

  it("deposit, withdraw collateral when position = 0", async () => {
    // wbtc
    const longAccountId = assembleSubAccountId(trader1.address, 0, 0, true)
    {
      await ensureFinished(orderBook.connect(trader1).depositCollateral(longAccountId, toWei("0.00001"), { value: toWei("0.00001") }))
      expect(await wbnb.balanceOf(pool.address)).to.equal(toWei("0.00001"))
    }
    {
      await ensureFinished(orderBook.connect(trader1).withdrawAllCollateral(longAccountId, { gasLimit: 2000000 }))
      expect(await wbnb.balanceOf(pool.address)).to.equal(toWei("0"))
    }
  })
})
