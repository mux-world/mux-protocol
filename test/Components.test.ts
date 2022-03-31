import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, OrderType, assembleSubAccountId, PositionOrderFlags } from "./deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber } from "@ethersproject/bignumber"
import { Context } from "mocha"
const U = ethers.utils

describe("Components", async () => {
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

  it("SafeOwnableUpgradeable", async () => {
    const ownable = await createContract("TestSafeOwnableUpgradeable")
    await ownable.initialize()

    expect(await ownable.owner()).to.equal(user0.address)
    expect(await ownable.pendingOwner()).to.equal(zeroAddress)

    await ownable.transferOwnership(user2.address)
    expect(await ownable.owner()).to.equal(user0.address)
    expect(await ownable.pendingOwner()).to.equal(user2.address)

    await expect(ownable.connect(user1).takeOwnership()).to.be.revertedWith("SND")
    await ownable.connect(user2).takeOwnership()
    expect(await ownable.owner()).to.equal(user2.address)
    expect(await ownable.pendingOwner()).to.equal(zeroAddress)

    await expect(ownable.connect(user1).renounceOwnership()).to.be.revertedWith("not the owner")
    await expect(ownable.connect(user2).transferOwnership(user2.address)).to.be.revertedWith("O=O")
    await expect(ownable.connect(user2).transferOwnership(zeroAddress)).to.be.revertedWith("O=0")
    await ownable.connect(user2).transferOwnership(user3.address)
    await ownable.connect(user2).renounceOwnership()
    expect(await ownable.owner()).to.equal(zeroAddress)
    expect(await ownable.pendingOwner()).to.equal(zeroAddress)
  })

  it("SafeOwnable", async () => {
    const ownable = await createContract("TestSafeOwnable")

    expect(await ownable.owner()).to.equal(user0.address)
    expect(await ownable.pendingOwner()).to.equal(zeroAddress)

    await ownable.transferOwnership(user2.address)
    expect(await ownable.owner()).to.equal(user0.address)
    expect(await ownable.pendingOwner()).to.equal(user2.address)

    await expect(ownable.connect(user1).takeOwnership()).to.be.revertedWith("SND")
    await ownable.connect(user2).takeOwnership()
    expect(await ownable.owner()).to.equal(user2.address)
    expect(await ownable.pendingOwner()).to.equal(zeroAddress)

    await expect(ownable.connect(user1).renounceOwnership()).to.be.revertedWith("not the owner")
    await expect(ownable.connect(user2).transferOwnership(user2.address)).to.be.revertedWith("O=O")
    await expect(ownable.connect(user2).transferOwnership(zeroAddress)).to.be.revertedWith("O=0")
    await ownable.connect(user2).transferOwnership(user3.address)
    await ownable.connect(user2).renounceOwnership()
    expect(await ownable.owner()).to.equal(zeroAddress)
    expect(await ownable.pendingOwner()).to.equal(zeroAddress)
  })
})
