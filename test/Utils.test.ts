import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { toWei, createContract, toBytes32, rate, assembleSubAccountId } from "./deployUtils"

describe("Utils", () => {
  it("toBytes32", () => {
    expect(toBytes32("a")).to.equal("0x6100000000000000000000000000000000000000000000000000000000000000")
  })

  it("rate", () => {
    expect(rate("1")).to.equal("100000")
    expect(rate("0.00001")).to.equal("1")
    expect(() => rate("0.000001")).to.throw("underflow")
  })

  it("assembleSubAccountId", () => {
    let encoded = assembleSubAccountId("0x5b38da6a701c568545dcfcb03fcb875f56beddc4", 1, 2, true)
    expect(encoded).to.equal("0x5b38da6a701c568545dcfcb03fcb875f56beddc4010201000000000000000000")
  })
})
