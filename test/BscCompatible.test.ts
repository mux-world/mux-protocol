import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, createFactory, ensureFinished, rate, PositionOrderFlags } from "./deployUtils"
import { createContract, assembleSubAccountId } from "./deployUtils"
import { MlpToken, TestOrderBook, TestLiquidityPool, WBNB, NativeUnwrapper, TestEthReceiver } from "../typechain"
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
    const nativeUnwrapper = (await createContract("NativeUnwrapper", [wbnb.address, { gasLimit: 1000000 }])) as NativeUnwrapper
    const libLiquidity = await createContract("LibLiquidity")
    const poolHop1 = await createContract("TestLiquidityPoolHop1")
    const poolHop2 = await createContract("TestLiquidityPoolHop2", [], { "contracts/libraries/LibLiquidity.sol:LibLiquidity": libLiquidity })
    const poolProxy = await createContract("TransparentUpgradeableProxy", [poolHop1.address, lp1.address /* admin */, "0x", { gasLimit: 1000000 }])
    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("TestOrderBook", [], { "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook })) as TestOrderBook
    console.log("bscTestnet wbnb", wbnb.address, "pool", poolProxy.address, "book", orderBook.address, "unwrap", nativeUnwrapper.address)
    console.log("bscTestnet contracts deployed")
    pool = await ethers.getContractAt("TestLiquidityPool", poolProxy.address)
    const mlp = "0x0000000000000000000000000000000000000000"
    await ensureFinished(orderBook.initialize(pool.address, mlp, wbnb.address, nativeUnwrapper.address))
    await ensureFinished(orderBook.addBroker(broker.address))
    await ensureFinished(pool.initialize(poolHop2.address, mlp, orderBook.address, wbnb.address, nativeUnwrapper.address, vault.address))
    await ensureFinished(nativeUnwrapper.addWhiteList(pool.address))
    await ensureFinished(nativeUnwrapper.addWhiteList(orderBook.address))
    console.log("bscTestnet contracts initialized")

    // 0 = BNB
    // id, symbol, decimals, stable, token, mux
    await ensureFinished(pool.addAsset(0, toBytes32("BNB"), 18, false, wbnb.address, wbnb.address))
    // id, symbol, imr, mmr, fee, fee, minBps, minTime, spotWeight
    await pool.setAssetParams(0, toBytes32("BNB"), rate("0.01"), rate("0.005"), rate("0.000"), rate("0.000"), rate("0.00"), 0, 0)
    // id, tradable, openable, shortable, useStable, enabled, strict, liq
    await ensureFinished(pool.setAssetFlags(0, true, true, true, false, true, false, true, rate("0"), toWei("10000000"), toWei("10000000")))
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

  it("if the trader is a normal contract", async () => {
    const ethReceiver = (await createContract("TestEthReceiver", [orderBook.address])) as TestEthReceiver

    // open
    const initialCollateral = toWei("0.00001")
    const subAccountId = assembleSubAccountId(ethReceiver.address, 0, 0, true)
    await ethReceiver.placePositionOrder3(
      subAccountId,
      initialCollateral, // collateral
      toWei("0.001"), // size
      toWei("0"), // price
      0, // profitTokenId
      PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder, // flags
      0, // deadline
      toBytes32(""), // referralCode
      {
        tpPrice: "0",
        slPrice: "0",
        tpslProfitTokenId: 0,
        tpslDeadline: 0,
      },
      { value: initialCollateral }
    )
    await orderBook.connect(broker).fillPositionOrder(0, toWei("300"), toWei("300"), toWei("300"))
    {
      const subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("0.00001"))
      expect(subAccount.size).to.equal(toWei("0.001"))
      expect(subAccount.entryPrice).to.equal(toWei("300"))
    }
    expect(await ethers.provider.getBalance(ethReceiver.address)).to.equal(toWei("0"))

    // liquidate
    await orderBook.connect(broker).liquidate(subAccountId, 0, toWei("298.5"), toWei("298.5"), toWei("298.5"), { gasLimit: 1000000 })
    {
      const subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
    }
    expect(await ethers.provider.getBalance(ethReceiver.address)).to.equal(toWei("0.000004974874371860"))
  })

  it("if the trader is a contract that consumes a lot gas", async () => {
    const ethReceiver = (await createContract("TestEthReceiver", [orderBook.address])) as TestEthReceiver

    // open
    const initialCollateral = toWei("0.00001")
    const subAccountId = assembleSubAccountId(ethReceiver.address, 0, 0, true)
    await ethReceiver.placePositionOrder3(
      subAccountId,
      initialCollateral, // collateral
      toWei("0.001"), // size
      toWei("0"), // price
      0, // profitTokenId
      PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder, // flags
      0, // deadline
      toBytes32(""), // referralCode
      {
        tpPrice: "0",
        slPrice: "0",
        tpslProfitTokenId: 0,
        tpslDeadline: 0,
      },
      { value: initialCollateral }
    )
    await orderBook.connect(broker).fillPositionOrder(0, toWei("300"), toWei("300"), toWei("300"))
    {
      const subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("0.00001"))
      expect(subAccount.size).to.equal(toWei("0.001"))
      expect(subAccount.entryPrice).to.equal(toWei("300"))
    }
    expect(await ethers.provider.getBalance(ethReceiver.address)).to.equal(toWei("0"))

    // liquidate
    await ensureFinished(ethReceiver.setGasDepletion(true))
    await orderBook.connect(broker).liquidate(subAccountId, 0, toWei("298.5"), toWei("298.5"), toWei("298.5"), { gasLimit: 1000000 })
    {
      const subAccount = await pool.getSubAccount(subAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
    }
    expect(await ethers.provider.getBalance(ethReceiver.address)).to.equal(toWei("0"))
    expect(await wbnb.balanceOf(ethReceiver.address)).to.equal(toWei("0.000004974874371860"))
  })
})
