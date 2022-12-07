import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { toWei, createContract, toBytes32, rate, assembleSubAccountId, PreMinedTokenTotalSupply, createFactory, toChainlink, ReferenceOracleType } from "./deployUtils"
import { TestLiquidityPool } from "../typechain"
const U = ethers.utils

describe("ChainedProxy", () => {
  let pool: TestLiquidityPool

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

  it("upgrade", async () => {
    const libLiquidity = await createContract("LibLiquidity")
    const poolHop1 = await createContract("TestLiquidityPoolHop1")
    const poolHop2 = await createContract("LiquidityPoolHop2", [], { "contracts/libraries/LibLiquidity.sol:LibLiquidity": libLiquidity })
    const poolHop2Upgrade = await createContract("TestLiquidityPoolHop2", [], { "contracts/libraries/LibLiquidity.sol:LibLiquidity": libLiquidity })
    pool = await ethers.getContractAt("TestLiquidityPool", poolHop1.address)
    await pool.initialize(poolHop2.address, user0.address /* test only */, user0.address /* test only */, user0.address /* test only */, user0.address /* test only */, user0.address /* test only */)

    await expect(pool.getFundingRatePublic("0", "0", "0", "0")).to.reverted
    await expect(pool.connect(user1).upgradeChainedProxy(poolHop2Upgrade.address)).to.revertedWith("Ownable: caller is not the owner")
    await pool.upgradeChainedProxy(poolHop2Upgrade.address)
    await pool.getFundingRatePublic("0", "0", "0", "0")
  })
})
