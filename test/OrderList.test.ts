import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { createContract } from "./deployUtils"
import { Contract } from "ethers"

describe("LibOrder - enumerable order list", () => {
  let orderBook: Contract
  let valueA = 1
  let valueB = 2
  let valueC = 3

  beforeEach(async () => {
    orderBook = await createContract("TestLibOrder")
  })

  async function expectMembersMatch(orders: number[]) {
    for (let orderId of orders) {
      const hasOrder = await orderBook.contains(orderId)
      expect(hasOrder).to.be.true

      const order = await orderBook.get(orderId)
      expect(order).to.equal(orderId)
    }

    const length = await orderBook.length()
    expect(length).to.equal(orders.length)

    const values: string[] = []
    for (let i = 0; i < length; i++) {
      const order = await orderBook.at(i)
      values.push(order.toString())
    }
    expect(values).to.have.same.members(orders.map((x) => x.toString()))
  }

  it("starts empty", async function () {
    expect(await orderBook.contains(valueA)).to.equal(false)
    await expectMembersMatch([])
  })

  describe("add", function () {
    it("adds a value", async function () {
      await orderBook.add(valueA)
      await expectMembersMatch([valueA])
    })

    it("adds several values", async function () {
      await orderBook.add(valueA)
      await orderBook.add(valueB)

      await expectMembersMatch([valueA, valueB])
      expect(await orderBook.contains(valueC)).to.equal(false)
    })

    it("returns false when adding values already in the set", async function () {
      await orderBook.add(valueA)
      await expect(orderBook.add(valueA)).to.revertedWith("DUP")
    })
  })

  describe("at", function () {
    it("reverts when retrieving non-existent elements", async function () {
      await expect(orderBook.at(0)).to.revertedWith("IDX")
    })
  })

  describe("remove", function () {
    it("removes added values", async function () {
      await orderBook.add(valueA)
      await orderBook.remove(valueA)

      expect(await orderBook.contains(valueA)).to.equal(false)
      await expectMembersMatch([])
    })

    it("returns false when removing values not in the set", async function () {
      await expect(orderBook.remove(valueA)).to.revertedWith("OID")
      expect(await orderBook.contains(valueA)).to.equal(false)
    })

    it("adds and removes multiple values", async function () {
      // []

      await orderBook.add(valueA)
      await orderBook.add(valueC)
      await expectMembersMatch([valueA, valueC])

      await orderBook.remove(valueA)
      await expect(orderBook.remove(valueB)).to.revertedWith("OID")
      await expectMembersMatch([valueC])

      await orderBook.add(valueB)
      await expectMembersMatch([valueC, valueB])

      await orderBook.add(valueA)
      await orderBook.remove(valueC)
      await expectMembersMatch([valueA, valueB])

      await expect(orderBook.add(valueA)).to.revertedWith("DUP")
      await expect(orderBook.add(valueB)).to.revertedWith("DUP")
      await expectMembersMatch([valueA, valueB])

      await orderBook.add(valueC)
      await orderBook.remove(valueA)
      await expectMembersMatch([valueC, valueB])

      await orderBook.add(valueA)
      await orderBook.remove(valueB)
      await expectMembersMatch([valueC, valueA])

      expect(await orderBook.contains(valueB)).to.equal(false)
    })
  })
})
