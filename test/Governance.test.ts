import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, createContract, toBytes32, rate, assembleSubAccountId, PreMinedTokenTotalSupply } from "./deployUtils"
const U = ethers.utils

describe("Trade", () => {
  let admin: Contract

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

  let zero = "0x0000000000000000000000000000000000000000000000000000000000000000"

  beforeEach(async () => {
    admin = await createContract("MuxTimelockController", [0, [user1.address], [user2.address]])
  })

  it("admin", async () => {
    const ownable = await createContract("TestSafeOwnable")
    await ownable.transferOwnership(admin.address)

    await expect(admin.schedule(ownable.address, 0, U.id("takeOwnership()").slice(0, 10), zero, zero, 0)).to.be.revertedWith(U.id("PROPOSER_ROLE"))
    await admin.connect(user1).schedule(ownable.address, 0, U.id("takeOwnership()").slice(0, 10), zero, zero, 0)
    await expect(admin.execute(ownable.address, 0, U.id("takeOwnership()").slice(0, 10), zero, zero)).to.be.revertedWith(U.id("EXECUTOR_ROLE"))
    await admin.connect(user2).execute(ownable.address, 0, U.id("takeOwnership()").slice(0, 10), zero, zero)
    expect(await ownable.owner()).to.equal(admin.address)
    await admin
      .connect(user1)
      .schedule(
        ownable.address,
        0,
        U.id("transferOwnership(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [user0.address]).slice(2),
        zero,
        zero,
        0
      )
    await admin
      .connect(user2)
      .execute(
        ownable.address,
        0,
        U.id("transferOwnership(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [user0.address]).slice(2),
        zero,
        zero
      )
    expect(await ownable.owner()).to.equal(admin.address)
    expect(await ownable.pendingOwner()).to.equal(user0.address)
  })

  it("quickPlugin", async () => {
    const p = await createContract("QuickTransferOwner")
    const ownable = await createContract("TestSafeOwnable")
    await ownable.transferOwnership(admin.address)
    await admin.connect(user1).schedule(ownable.address, 0, U.id("takeOwnership()").slice(0, 10), zero, zero, 0)
    await admin.connect(user2).execute(ownable.address, 0, U.id("takeOwnership()").slice(0, 10), zero, zero)

    await expect(admin.addQuickPath(p.address)).to.revertedWith("S!T");
    await admin.connect(user1).schedule(
      admin.address,
      0,
      U.id("addQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      zero,
      0
    )
    await admin.connect(user2).execute(
      admin.address,
      0,
      U.id("addQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      zero
    )
    await admin.connect(user2).executeQuickPath(
      p.address,
      U.id("transferOwnership(address,address)").slice(0, 10) + U.defaultAbiCoder.encode(["address", "address"], [ownable.address, user3.address]).slice(2)
    )
    expect(await ownable.pendingOwner()).to.equal(user3.address)
    await ownable.connect(user3).takeOwnership();

    await admin.connect(user1).schedule(
      admin.address,
      0,
      U.id("removeQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      zero,
      0
    )
    await expect(admin.connect(user3).removeQuickPath(p.address)).to.be.revertedWith("S!T")

    await admin.connect(user2).execute(
      admin.address,
      0,
      U.id("removeQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      zero
    )
    await expect(admin.connect(user2).executeQuickPath(
      p.address,
      U.id("transferOwnership(address,address)").slice(0, 10) + U.defaultAbiCoder.encode(["address", "address"], [ownable.address, user3.address]).slice(2)
    )).to.be.revertedWith("!QP")
  })

  it("quickPlugin2", async () => {
    const p = await createContract("QuickTransferOwner")
    const ownable = await createContract("TestSafeOwnable")
    await ownable.transferOwnership(admin.address)
    await admin.connect(user1).schedule(ownable.address, 0, U.id("takeOwnership()").slice(0, 10), zero, zero, 0)
    await admin.connect(user2).execute(ownable.address, 0, U.id("takeOwnership()").slice(0, 10), zero, zero)
    await admin.connect(user1).schedule(
      admin.address,
      0,
      U.id("addQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      zero,
      0
    )
    await admin.connect(user2).execute(
      admin.address,
      0,
      U.id("addQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      zero
    )
    await admin.connect(user1).schedule(
      admin.address,
      0,
      U.id("addQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      toBytes32("123"),
      0
    )
    await expect(admin.connect(user2).execute(
      admin.address,
      0,
      U.id("addQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      toBytes32("123"),
    )).to.be.revertedWith("underlying transaction reverted")

    await admin.connect(user1).schedule(
      admin.address,
      0,
      U.id("removeQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      zero,
      0
    )
    await admin.connect(user2).execute(
      admin.address,
      0,
      U.id("removeQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      zero
    )

    await admin.connect(user1).schedule(
      admin.address,
      0,
      U.id("removeQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      toBytes32("123"),
      0
    )
    await expect(admin.connect(user2).execute(
      admin.address,
      0,
      U.id("removeQuickPath(address)").slice(0, 10) + U.defaultAbiCoder.encode(["address"], [p.address]).slice(2),
      zero,
      toBytes32("123")
    )).to.be.revertedWith("underlying transaction reverted")

  })
})
