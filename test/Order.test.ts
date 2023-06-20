import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, OrderType, assembleSubAccountId, PositionOrderFlags, hashString, toBytes32, rate } from "./deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber } from "@ethersproject/bignumber"
import { TestOrderBook } from "../typechain"
const U = ethers.utils

function getOrderType(orderData: string[]): number {
  return BigNumber.from(U.arrayify(orderData[0])[31]).toNumber()
}

function parsePositionOrder(orderData: string[]) {
  const arr = orderData.map((x: any) => U.arrayify(x))
  const flags = BigNumber.from(arr[1].slice(13, 14)).toNumber()
  return {
    id: BigNumber.from(arr[0].slice(23, 31)).toNumber(),
    subAccountId: U.hexlify(U.concat([arr[0].slice(0, 23), U.zeroPad([], 9)])),
    collateral: BigNumber.from(arr[2].slice(12, 24)),
    size: BigNumber.from(arr[1].slice(0, 12)),
    price: BigNumber.from(arr[2].slice(0, 12)),
    profitTokenId: BigNumber.from(arr[1].slice(12, 13)),
    isOpenPosition: (flags & 0x80) > 0,
    isMarketOrder: (flags & 0x40) > 0,
    isWithdrawAllIfEmpty: (flags & 0x20) > 0,
    isTriggerOrder: (flags & 0x10) > 0,
    placeOrderTime: BigNumber.from(arr[1].slice(20, 24)).toNumber(),
    expire10s: BigNumber.from(arr[1].slice(17, 20)).toNumber(),
  }
}

function parseLiquidityOrder(orderData: string[]) {
  const arr = orderData.map((x: any) => U.arrayify(x))
  const flags = BigNumber.from(arr[1].slice(13, 14)).toNumber()
  return {
    id: BigNumber.from(arr[0].slice(23, 31)).toNumber(),
    account: U.hexlify(arr[0].slice(0, 20)),
    rawAmount: BigNumber.from(arr[1].slice(0, 12)),
    assetId: BigNumber.from(arr[1].slice(12, 13)).toNumber(),
    isAdding: flags > 0,
    placeOrderTime: BigNumber.from(arr[1].slice(20, 24)).toNumber(),
  }
}

function parseWithdrawalOrder(orderData: string[]) {
  const arr = orderData.map((x: any) => U.arrayify(x))
  const flags = BigNumber.from(arr[1].slice(13, 14)).toNumber()
  return {
    id: BigNumber.from(arr[0].slice(23, 31)).toNumber(),
    subAccountId: U.hexlify(U.concat([arr[0].slice(0, 23), U.zeroPad([], 9)])),
    rawAmount: BigNumber.from(arr[1].slice(0, 12)),
    profitTokenId: BigNumber.from(arr[1].slice(12, 13)).toNumber(),
    isProfit: flags > 0,
    placeOrderTime: BigNumber.from(arr[1].slice(20, 24)).toNumber(),
  }
}

function parseRebalanceOrder(orderData: string[]) {
  const arr = orderData.map((x: any) => U.arrayify(x))
  return {
    id: BigNumber.from(arr[0].slice(23, 31)).toNumber(),
    rebalancer: U.hexlify(arr[0].slice(0, 20)),
    tokenId0: BigNumber.from(arr[0].slice(20, 21)).toNumber(),
    tokenId1: BigNumber.from(arr[0].slice(21, 22)).toNumber(),
    rawAmount0: BigNumber.from(arr[1].slice(0, 12)),
    maxRawAmount1: BigNumber.from(arr[1].slice(12, 24)),
    userData: Buffer.from(arr[2]),
  }
}

describe("Order", () => {
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  const refCode = toBytes32("")
  const posExtra = {
    tpPrice: "0",
    slPrice: "0",
    tpslProfitTokenId: 0,
    tpslDeadline: 0,
  }
  let orderBook: TestOrderBook
  let pool: Contract
  let mlp: Contract
  let atk: Contract
  let ctk: Contract

  let user0: SignerWithAddress
  let broker: SignerWithAddress

  before(async () => {
    const accounts = await ethers.getSigners()
    user0 = accounts[0]
    broker = accounts[1]
  })

  beforeEach(async () => {
    ctk = await createContract("MockERC20", ["CTK", "CTK", 18])
    atk = await createContract("MockERC20", ["ATK", "ATK", 18])
    mlp = await createContract("MockERC20", ["MLP", "MLP", 18])

    pool = await createContract("MockLiquidityPool")
    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("TestOrderBook", [], { "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook })) as TestOrderBook
    await orderBook.initialize(pool.address, mlp.address, weth9, weth9)
    await orderBook.addBroker(broker.address)
    await orderBook.setBlockTimestamp(1000)
    await orderBook.setOrderTimeout(300, 86400 * 365)

    await pool.setAssetAddress(0, ctk.address)
    await pool.setAssetAddress(1, atk.address)
  })

  it("placeOrder", async () => {
    {
      await ctk.approve(orderBook.address, toWei("1"))
      await ctk.mint(user0.address, toWei("1"))
      await orderBook.placePositionOrder3(
        assembleSubAccountId(user0.address, 0, 1, true),
        toWei("1"),
        toWei("0.2"),
        toWei("3000"),
        0,
        PositionOrderFlags.OpenPosition,
        1000 + 86400 * 30,
        refCode,
        posExtra
      )
      expect(await orderBook.getOrderCount()).to.equal(1)
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderArray.length).to.equal(1)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(true)
      expect(getOrderType(result[0])).to.equal(OrderType.Position)

      const order = parsePositionOrder(result[0])
      expect(order.id).to.equal(0)
      expect(order.subAccountId).to.equal(assembleSubAccountId(user0.address, 0, 1, true))
      expect(order.collateral).to.equal(toWei("1"))
      expect(order.size).to.equal(toWei("0.2"))
      expect(order.price).to.equal(toWei("3000"))
      expect(order.profitTokenId).to.equal(0)
      expect(order.isOpenPosition).to.equal(true)
      expect(order.isMarketOrder).to.equal(false)
      expect(order.isWithdrawAllIfEmpty).to.equal(false)
      expect(order.isTriggerOrder).to.equal(false)
      expect(order.placeOrderTime).to.equal(1000)
      expect(order.expire10s).to.equal((86400 * 30) / 10)
      expect(await ctk.balanceOf(user0.address)).to.equal(0)
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("1"))
    }
    {
      await atk.approve(orderBook.address, toWei("40"))
      await atk.mint(user0.address, toWei("40"))
      await orderBook.placeLiquidityOrder(1, toWei("40"), true)
      expect(await orderBook.getOrderCount()).to.equal(2)
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(2)
        expect(orders.orderArray.length).to.equal(2)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(true)

      expect(getOrderType(result[0])).to.equal(OrderType.Liquidity)
      const order = parseLiquidityOrder(result[0])
      expect(order.id).to.equal(1)
      expect(order.account).to.equal(user0.address.toLowerCase())
      expect(order.rawAmount).to.equal(toWei("40"))
      expect(order.assetId).to.equal(1)
      expect(order.isAdding).to.equal(true)
      expect(order.placeOrderTime).to.equal(1000)
    }
    {
      await orderBook.placeWithdrawalOrder(assembleSubAccountId(user0.address, 0, 1, true), toWei("500"), 1, true)
      expect(await orderBook.getOrderCount()).to.equal(3)
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(3)
        expect(orders.orderArray.length).to.equal(3)
      }
      const result = await orderBook.getOrder(2)
      expect(result[1]).to.equal(true)

      expect(getOrderType(result[0])).to.equal(OrderType.Withdrawal)
      const order = parseWithdrawalOrder(result[0])
      expect(order.id).to.equal(2)
      expect(order.subAccountId).to.equal(assembleSubAccountId(user0.address, 0, 1, true))
      expect(order.rawAmount).to.equal(toWei("500"))
      expect(order.profitTokenId).to.equal(1)
      expect(order.isProfit).to.equal(true)
      expect(order.placeOrderTime).to.equal(1000)
    }
    {
      await orderBook.addRebalancer(user0.address)
      await orderBook.placeRebalanceOrder(0, 1, toWei("2"), toWei("500"), hashString("random"))
      expect(await orderBook.getOrderCount()).to.equal(4)
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(4)
        expect(orders.orderArray.length).to.equal(4)
      }
      const result = await orderBook.getOrder(3)
      expect(result[1]).to.equal(true)

      expect(getOrderType(result[0])).to.equal(OrderType.Rebalance)
      const order = parseRebalanceOrder(result[0])
      expect(order.id).to.equal(3)
      expect(order.rebalancer.toLowerCase()).to.equal(user0.address.toLowerCase())
      expect(order.tokenId0).to.equal(0)
      expect(order.tokenId1).to.equal(1)
      expect(order.rawAmount0).to.equal(toWei("2"))
      expect(order.maxRawAmount1).to.equal(toWei("500"))
      expect(order.userData.toString("hex")).to.equal(hashString("random").toString("hex"))
    }
  })

  it("placePositionOrder - open long position", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    // no1
    {
      await orderBook.placePositionOrder3(
        assembleSubAccountId(user0.address, 0, 1, true),
        toWei("100"),
        toWei("0.1"),
        toWei("1000"),
        0,
        PositionOrderFlags.OpenPosition,
        1000 + 86400,
        refCode,
        posExtra
      )
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderArray.length).to.equal(1)
      }

      await orderBook.cancelOrder(0)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // no2
    {
      await orderBook.placePositionOrder3(
        assembleSubAccountId(user0.address, 0, 1, true),
        toWei("100"),
        toWei("0.1"),
        toWei("1000"),
        0,
        PositionOrderFlags.OpenPosition,
        1000 + 86400,
        refCode,
        posExtra
      )
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderArray.length).to.equal(1)
      }
      await orderBook.connect(broker).fillPositionOrder(1, toWei("2000"), toWei("1000"), toWei("1"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await ctk.balanceOf(pool.address)).to.equal(toWei("100"))
    }
  })

  it("close long position - must profit", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
    // open
    await pool.openPosition(
      subAccountId,
      toWei('0.1'), // amount
      toWei('0.1'), // collateralPrice
      toWei('1000'), // assetPrice
    );
    // place close - fail
    {
      await expect(orderBook.placePositionOrder3(
        subAccountId,
        toWei("0"),
        toWei("0.1"),
        toWei("0"),
        1,
        PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
        1000 + 86400,
        refCode,
        posExtra
      )).to.revertedWith("MPT")
    }
    // place close - success
    {
      await pool.setAssetAddress(1, atk.address)
      await pool.setAssetParams(1, 60, rate('0.10'))
      await orderBook.placePositionOrder3(
        subAccountId,
        toWei("0"),
        toWei("0.1"),
        toWei("0"),
        1,
        PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
        1000 + 86400,
        refCode,
        posExtra
      )
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderArray.length).to.equal(1)
      }
    }
    // place close - profit/time not reached
    {
      await expect(orderBook.connect(broker).fillPositionOrder(0, toWei("2000"), toWei("1001"), toWei("1")))
        .to.revertedWith("PFT")
      const orders = await orderBook.getOrders(0, 100)
      expect(orders.totalCount).to.equal(1)
      expect(orders.orderArray.length).to.equal(1)
    }
    // place close - profit reached
    {
      await expect(orderBook.connect(broker).fillPositionOrder(0, toWei("2000"), toWei("1010"), toWei("1")))
    }
  })

  it("placeLiquidityOrder - addLiquidity", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    // no1
    {
      await orderBook.placeLiquidityOrder(0, toWei("150"), true)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("850"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("150"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderArray.length).to.equal(1)
      }

      await orderBook.cancelOrder(0)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderArray.length).to.equal(0)
      }

      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // no2
    {
      await orderBook.placeLiquidityOrder(0, toWei("150"), true)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("850"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("150"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderArray.length).to.equal(1)
      }

      const current = toWei("29700")
      const target = toWei("29700")
      await orderBook.connect(broker).fillLiquidityOrder(1, toWei("2000"), toWei("1000"), current, target)
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)

      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("850"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await ctk.balanceOf(pool.address)).to.equal(toWei("150"))
    }
  })

  it("placeLiquidityOrder - removeLiquidity", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    // add liquidity
    {
      await orderBook.placeLiquidityOrder(0, toWei("150"), true)
      const current = toWei("29700")
      const target = toWei("29700")
      await orderBook.connect(broker).fillLiquidityOrder(0, toWei("2000"), toWei("1000"), current, target)
    }
    expect(await mlp.balanceOf(user0.address)).to.equal(toWei("0")) // because this test uses a mocked liquidity pool
    await mlp.mint(user0.address, toWei("2"))
    // no1
    await mlp.approve(orderBook.address, toWei("2"))
    {
      await orderBook.placeLiquidityOrder(0, toWei("1"), false)
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("1"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderArray.length).to.equal(1)
      }

      await orderBook.cancelOrder(1)
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("2"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderArray.length).to.equal(0)
      }

      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // no2
    {
      await orderBook.placeLiquidityOrder(0, toWei("1"), false)
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("1"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderArray.length).to.equal(1)
      }

      const current = toWei("29700")
      const target = toWei("29700")
      await orderBook.connect(broker).fillLiquidityOrder(2, toWei("2000"), toWei("1000"), current, target)
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)

      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("1"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("1"))
    }
  })

  it("removeBroker, renounceBroker", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    const current = toWei("29700")
    const target = toWei("29700")

    await orderBook.placeLiquidityOrder(0, toWei("150"), true)
    await orderBook.removeBroker(broker.address)
    await expect(orderBook.connect(broker).fillLiquidityOrder(0, toWei("2000"), toWei("1000"), current, target)).to.revertedWith("BKR")

    await orderBook.addBroker(broker.address)
    await orderBook.connect(broker).fillLiquidityOrder(0, toWei("2000"), toWei("1000"), current, target)

    await orderBook.placeLiquidityOrder(0, toWei("150"), true)
    await orderBook.connect(broker).renounceBroker()
    await expect(orderBook.connect(broker).fillLiquidityOrder(1, toWei("2000"), toWei("1000"), current, target)).to.revertedWith("BKR")

    await orderBook.addBroker(broker.address)
    await orderBook.connect(broker).fillLiquidityOrder(1, toWei("2000"), toWei("1000"), current, target)
  })

  it("broker can cancel orders", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    // limit order
    {
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
      await expect(orderBook.placePositionOrder3(subAccountId, toWei("100"), toWei("0.1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 1000 + 167772160, refCode, posExtra)).revertedWith("DTL")
      await expect(orderBook.placePositionOrder3(subAccountId, toWei("100"), toWei("0.1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 1000 + 86400, refCode, posExtra))
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(subAccountId, 0, toWei("100"), toWei("0.1"), toWei("1000"), 0, PositionOrderFlags.OpenPosition, 1000 + 86400)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))

      await orderBook.setBlockTimestamp(1000 + 86400)
      await expect(orderBook.connect(broker).cancelOrder(0)).revertedWith("EXP")
      await orderBook.setBlockTimestamp(1000 + 86410)
      await orderBook.connect(broker).cancelOrder(0)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // withdraw order
    {
      await orderBook.placeWithdrawalOrder(assembleSubAccountId(user0.address, 0, 1, true), toWei("500"), 1, true)
      await orderBook.setBlockTimestamp(1000 + 86410 + 300)
      await expect(orderBook.connect(broker).cancelOrder(1)).revertedWith("EXP")
      await orderBook.setBlockTimestamp(1000 + 86410 + 310)
      await orderBook.connect(broker).cancelOrder(1)
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // market order
    {
      const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
      await expect(
        orderBook.placePositionOrder3(subAccountId, toWei("100"), toWei("0.1"), toWei("0"), 0, PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder, 1000 + 167772160, refCode, posExtra)
      ).revertedWith("D!0")
      await expect(orderBook.placePositionOrder3(subAccountId, toWei("100"), toWei("0.1"), toWei("0"), 0, PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder, 0, refCode, posExtra))
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(subAccountId, 2, toWei("100"), toWei("0.1"), toWei("0"), 0, PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder, 0)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))

      await orderBook.setBlockTimestamp(1000 + 86410 + 310 + 300)
      await expect(orderBook.connect(broker).cancelOrder(2)).revertedWith("EXP")
      await orderBook.setBlockTimestamp(1000 + 86410 + 310 + 310)
      await orderBook.connect(broker).cancelOrder(2)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
  })
})
