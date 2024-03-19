import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, toUnit, toBytes32, createFactory, ensureFinished, rate, PositionOrderFlags } from "./deployUtils"
import { createContract, assembleSubAccountId } from "./deployUtils"
import { MlpToken, TestOrderBook, TestLiquidityPool, WBNB, XXX, TestEthReceiver } from "../typechain"
const U = ethers.utils

describe("BscCompatible - this test should be tested on bscTestnet", () => {
  let wbnb: WBNB

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
    const nativeUnwrapper = (await createContract("XXX", [wbnb.address, { gasLimit: 1000000 }])) as XXX
    console.log("bscTestnet contracts initialized")
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
