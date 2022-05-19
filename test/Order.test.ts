import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, OrderType, assembleSubAccountId, PositionOrderFlags, rate } from "./deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber } from "@ethersproject/bignumber"
import { OrderBook } from "../typechain"
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
    isMarketOrder: (flags & 0x40) > 0,
    isIncreasing: (flags & 0x80) > 0,
  }
}

function parseLiquidityOrder(orderData: string[]) {
  const arr = orderData.map((x: any) => U.arrayify(x))
  const flags = BigNumber.from(arr[1].slice(13, 14)).toNumber()
  return {
    id: BigNumber.from(arr[0].slice(23, 31)).toNumber(),
    account: U.hexlify(arr[0].slice(0, 20)),
    amount: BigNumber.from(arr[1].slice(0, 12)),
    assetId: BigNumber.from(arr[1].slice(12, 13)).toNumber(),
    isAdding: flags > 0,
    addLiquidityTime: BigNumber.from(arr[1].slice(20, 24)).toNumber(),
  }
}

function parseWithdrawalOrder(orderData: string[]) {
  const arr = orderData.map((x: any) => U.arrayify(x))
  const flags = BigNumber.from(arr[1].slice(13, 14)).toNumber()
  return {
    id: BigNumber.from(arr[0].slice(23, 31)).toNumber(),
    subAccountId: U.hexlify(U.concat([arr[0].slice(0, 23), U.zeroPad([], 9)])),
    amount: BigNumber.from(arr[1].slice(0, 12)),
    profitTokenId: BigNumber.from(arr[1].slice(12, 13)).toNumber(),
    isProfit: flags > 0,
  }
}

describe("Order", () => {
  const weth9 = "0x0000000000000000000000000000000000000000" // this test file will not use weth
  let orderBook: OrderBook
  let pool: Contract
  let mlp: Contract
  let atk: Contract
  let ctk: Contract

  let user0: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let user3: SignerWithAddress

  before(async () => {
    const accounts = await ethers.getSigners()
    user0 = accounts[0]
    user1 = accounts[1]
    user2 = accounts[2]
    user3 = accounts[3]
  })

  beforeEach(async () => {
    ctk = await createContract("MockERC20", ["CTK", "CTK", 18])
    atk = await createContract("MockERC20", ["ATK", "ATK", 18])
    mlp = await createContract("MockERC20", ["MLP", "MLP", 18])

    pool = await createContract("MockLiquidityPool")
    orderBook = (await createContract("OrderBook")) as OrderBook
    await orderBook.initialize(pool.address, mlp.address, weth9, weth9)
    await orderBook.addBroker(user0.address)

    await pool.setAssetAddress(0, ctk.address)
    await pool.setAssetAddress(1, atk.address)
  })

  it("placeOrder", async () => {
    {
      await ctk.approve(orderBook.address, toWei("1"))
      await ctk.mint(user0.address, toWei("1"))
      await orderBook.placePositionOrder(
        assembleSubAccountId(user0.address, 0, 1, true),
        toWei("1"),
        toWei("0.2"),
        toWei("3000"),
        1,
        PositionOrderFlags.OpenPosition
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
      expect(order.profitTokenId).to.equal(1)
      expect(order.isMarketOrder).to.equal(false)
      expect(order.isIncreasing).to.equal(true)

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
      expect(order.amount).to.equal(toWei("40"))
      expect(order.assetId).to.equal(1)
      expect(order.isAdding).to.equal(true)
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
      expect(order.amount).to.equal(toWei("500"))
      expect(order.profitTokenId).to.equal(1)
      expect(order.isProfit).to.equal(true)
    }
  })

  it("placePositionOrder - open long position", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    // no1
    {
      await orderBook.placePositionOrder(
        assembleSubAccountId(user0.address, 0, 1, true),
        toWei("100"),
        toWei("0.1"),
        toWei("1000"),
        0,
        PositionOrderFlags.OpenPosition
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
      await orderBook.placePositionOrder(
        assembleSubAccountId(user0.address, 0, 1, true),
        toWei("100"),
        toWei("0.1"),
        toWei("1000"),
        0,
        PositionOrderFlags.OpenPosition
      )
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderArray.length).to.equal(1)
      }

      await orderBook.fillPositionOrder(1, toWei("2000"), toWei("1000"), toWei("1"))
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
      await orderBook.fillLiquidityOrder(1, toWei("2000"), toWei("1000"), current, target)
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
      await orderBook.fillLiquidityOrder(0, toWei("2000"), toWei("1000"), current, target)
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
      await orderBook.fillLiquidityOrder(2, toWei("2000"), toWei("1000"), current, target)
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
    await orderBook.removeBroker(user0.address)
    await expect(orderBook.fillLiquidityOrder(0, toWei("2000"), toWei("1000"), current, target)).to.revertedWith("BKR")

    await orderBook.addBroker(user0.address)
    await orderBook.fillLiquidityOrder(0, toWei("2000"), toWei("1000"), current, target)

    await orderBook.placeLiquidityOrder(0, toWei("150"), true)
    await orderBook.renounceBroker()
    await expect(orderBook.fillLiquidityOrder(1, toWei("2000"), toWei("1000"), current, target)).to.revertedWith("BKR")

    await orderBook.addBroker(user0.address)
    await orderBook.fillLiquidityOrder(1, toWei("2000"), toWei("1000"), current, target)
  })
})
