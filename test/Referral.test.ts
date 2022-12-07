import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, OrderType, assembleSubAccountId, PositionOrderFlags, toBytes32 } from "./deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber } from "@ethersproject/bignumber"
import { Context } from "mocha"
const U = ethers.utils

describe("Disperse", async () => {
    let user0: SignerWithAddress
    let user1: SignerWithAddress
    let user2: SignerWithAddress
    let user3: SignerWithAddress
    let user4: SignerWithAddress

    let zeroAddress = "0x0000000000000000000000000000000000000000"

    before(async () => {
        const accounts = await ethers.getSigners()
        user0 = accounts[0]
        user1 = accounts[1]
        user2 = accounts[2]
        user3 = accounts[3]
        user4 = accounts[4]
    })

    it("ReferralManager", async () => {
        const rmgr = await createContract("TestReferralManager")
        await rmgr.initialize()

        console.log(await rmgr.getTiers())
        await rmgr.setTiers([
            { tier: 0, stakeThreshold: 0, discountRate: 2500, rebateRate: 2500 },
            { tier: 1, stakeThreshold: 25000, discountRate: 5000, rebateRate: 5000 },
            { tier: 2, stakeThreshold: 50000, discountRate: 5000, rebateRate: 10000 },
            { tier: 3, stakeThreshold: 250000, discountRate: 5000, rebateRate: 20000 },
            { tier: 4, stakeThreshold: 500000, discountRate: 5000, rebateRate: 25000 },
            { tier: 5, stakeThreshold: 1000000, discountRate: 5000, rebateRate: 35000 },
        ])
        console.log(await rmgr.getTiers())

        await rmgr.setTiers([
            { tier: 0, stakeThreshold: 0, discountRate: 2500, rebateRate: 2500 },
            { tier: 1, stakeThreshold: 25000, discountRate: 5000, rebateRate: 5000 },
            { tier: 2, stakeThreshold: 50000, discountRate: 5000, rebateRate: 10000 },
        ])
        console.log(await rmgr.getTiers())

        console.log(await rmgr.getTiers())
        await rmgr.setTiers([
            { tier: 0, stakeThreshold: 0, discountRate: 2500, rebateRate: 2500 },
            { tier: 1, stakeThreshold: 99, discountRate: 5000, rebateRate: 5000 },
            { tier: 2, stakeThreshold: 999, discountRate: 5000, rebateRate: 10000 },
            { tier: 3, stakeThreshold: 9999, discountRate: 5000, rebateRate: 20000 },
            { tier: 4, stakeThreshold: 99999, discountRate: 5000, rebateRate: 25000 },
        ])
        console.log(await rmgr.getTiers())
    })

    it("Disperse", async () => {
        const weth = await createContract("MockERC20", ["WETH", "WETH", 18])

        const disperse = await createContract("Disperse")
        await disperse.initialize()
        await disperse.setToken(weth.address)
        await disperse.setMaintainer(user0.address)

        await weth.mint(user0.address, toWei("1000"))
        await weth.approve(disperse.address, toWei("1000"))

        await expect(disperse.disperseReferrerRebate(
            user1.address,
            100,
            [
                toBytes32("CodeA"),
                toBytes32("CodeB"),
                toBytes32("CodeC"),
            ],
            [
                user1.address,
                user1.address,

            ],
            [
                toWei("10"),
                toWei("40"),
                toWei("50")
            ],
            toWei("1")
        )).to.be.revertedWith("ParamLengthMismatch")

        await disperse.disperseReferrerRebate(
            user1.address,
            100,
            [
                toBytes32("CodeA"),
                toBytes32("CodeB"),
                toBytes32("CodeC"),
            ],
            [
                user1.address,
                user1.address,
                user2.address,

            ],
            [
                toWei("10"),
                toWei("40"),
                toWei("50")
            ],
            toWei("1")
        )
        expect(await weth.balanceOf(user1.address)).to.equal(toWei("50"))
        expect(await weth.balanceOf(user2.address)).to.equal(toWei("50"))

        await expect(disperse.disperseTraderDiscount(
            100,
            [ethers.utils.formatBytes32String("A"), ethers.utils.formatBytes32String("B")],
            [user2.address, user3.address],
            [toWei("10"), toWei("20"), toWei("30")],
            toWei("1")
        )).to.be.revertedWith("ParamLengthMismatch")

        await disperse.disperseTraderDiscount(
            100,
            [ethers.utils.formatBytes32String("A"), ethers.utils.formatBytes32String("B"), ethers.utils.formatBytes32String("C")],
            [user2.address, user3.address, user4.address],
            [toWei("10"), toWei("20"), toWei("30")],
            toWei("1")
        )
        expect(await weth.balanceOf(user2.address)).to.equal(toWei("60"))
        expect(await weth.balanceOf(user3.address)).to.equal(toWei("20"))
        expect(await weth.balanceOf(user4.address)).to.equal(toWei("30"))
    })
})
