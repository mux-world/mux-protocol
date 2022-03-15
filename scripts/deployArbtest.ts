import hre, { ethers } from "hardhat"
import { restorableEnviron } from "./deployer/environ"
import { toWei, toUnit, toBytes32, rate, ensureFinished, AdminParamsType, AdminParamsAbi } from "../test/deployUtils"
import { Deployer, DeploymentOptions } from "./deployer/deployer"
import { LiquidityPool, OrderBook, LiquidityManager, Reader } from "../typechain"
import { MuxToken, MlpToken, MockERC20 } from "../typechain"
import { ContractReceipt } from "ethers"

const proxyAdmin = "0x1D34658aD1259F515246335A11372Fe51330999d"
const broker = "0x42C8C75a256A18f78a5834b84C3945a3aA012B56"

const ENV: DeploymentOptions = {
  network: hre.network.name,
  artifactDirectory: "./artifacts/contracts",
  addressOverride: {
    // ArbRinkeby
    WETH9: "0xB47e6A5f8b33b3F17603C83a0535A9dcD7E32681",
  },
}

async function faucet(deployer: Deployer) {
  console.log("faucet")
  const usdc: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockUsdc", "USD Coin", "USDC", 6)
  const weth: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockWeth", "Wrapped ETH", "WETH", 18)
  for (let a of [
    // "0xba893CfA648f46F92a29911589f1A353b6AA4938", // t1
    // "0x1C1d586FB6e0A1645236a32aB4B20776C522e3AD", // t2
    // '0x3E67F481088cFBbDDffbE502A2D2B976b4be6029', // ma
    // "0xe87c5839421579552e676Ab0627aE03A7bf9B6d1", // hu
    // "0x38289729cf9A0007bC713874C54d30298E31f9D2", // ya
    // "0x26a3D521FdFb6B90F7971d1f856B91f925bacf83", // we
  ]) {
    console.log("to", a)
    const tx1 = await usdc.mint(a, toUnit("200000", 6))
    const tx2 = await weth.mint(a, toWei("100"))
    console.log(tx1.hash, tx2.hash)
  }
}

async function preset1(deployer: Deployer) {
  console.log("preset1")
  const accounts = await ethers.getSigners()
  const pool: LiquidityPool = await deployer.getDeployedContract("LiquidityPool", "LiquidityPool")
  const orderBook: OrderBook = await deployer.getDeployedContract("OrderBook", "OrderBook")
  const liquidityManager: LiquidityManager = await deployer.getDeployedContract("LiquidityManager", "LiquidityManager")

  // deploy
  const usdc: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockUsdc", "USD Coin", "USDC", 6)
  const weth: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockWeth", "Wrapped ETH", "WETH", 18)
  const muxUsdc: MuxToken = await deployer.deployOrSkip("MuxToken", "MuxUsdc", "MuxToken for USDC", "MuxUSDC")
  const muxWeth: MuxToken = await deployer.deployOrSkip("MuxToken", "MuxWeth", "MuxToken for WETH", "MuxWETH")

  console.log("transfer mux")
  await muxUsdc.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await muxWeth.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)

  console.log("add usdc")
  // id, symbol, decimals, stable, token, mux
  await pool.setParams(
    AdminParamsType.AddAsset,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.AddAsset, [
      0,
      toBytes32("USDC"),
      6,
      true,
      usdc.address,
      muxUsdc.address,
    ])
  )
  // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
  await pool.setParams(
    AdminParamsType.SetAssetParams,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetParams, [
      0,
      rate("0"),
      rate("0"),
      rate("0"),
      rate("0"),
      0,
      toWei("0"),
      toWei("0"),
      1,
      "0x0000000000000000000000000000000000000000",
      0,
    ])
  )
  // id, tradable, openable, shortable, useStable
  await pool.setParams(
    AdminParamsType.SetAssetFlags,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetFlags, [0, false, false, false, false])
  )
  await pool.setParams(
    AdminParamsType.SetFundingParams,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetFundingParams, [0, rate("0.0001"), rate("0.0008")])
  )

  console.log("add weth")
  // id, symbol, decimals, stable, token, mux
  await pool.setParams(
    AdminParamsType.AddAsset,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.AddAsset, [
      1,
      toBytes32("ETH"),
      18,
      false,
      weth.address,
      muxWeth.address,
    ])
  )
  // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, oracle, oracle
  await pool.setParams(
    AdminParamsType.SetAssetParams,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetParams, [
      1,
      rate("0.02"),
      rate("0.01"),
      rate("0.001"),
      rate("0.001"),
      60,
      toWei("10000000"),
      toWei("10000000"),
      2,
      "0x0000000000000000000000000000000000000000",
      0,
    ])
  )
  // id, tradable, openable, shortable, useStable
  await pool.setParams(
    AdminParamsType.SetAssetFlags,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAssetFlags, [1, true, true, true, false])
  )
  await pool.setParams(
    AdminParamsType.SetFundingParams,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetFundingParams, [1, rate("0.0003"), rate("0.0008")])
  )

  console.log("add weth-usdc")
  await ensureFinished(liquidityManager.addDexSpotConfiguration(3, [0, 1], [4, 5]))

  // liquidity usdc
  console.log("add liquidity")
  await ensureFinished(usdc.approve(orderBook.address, toUnit("1000000", 6)))
  const tx1 = (await ensureFinished(orderBook.placeLiquidityOrder(0, toUnit("1000000", 6), true))) as ContractReceipt
  let orderId = "0"
  for (let event of tx1.events!) {
    if (event.event === "NewLiquidityOrder") {
      orderId = event.args!.orderId.toString()
      console.log("orderId:", orderId)
    }
  }
  await ensureFinished(orderBook.connect(accounts[1]).fillLiquidityOrder(orderId, toWei("1"), toWei("1")))
}

async function main(deployer: Deployer) {
  const accounts = await ethers.getSigners()

  // deploy
  const mlpToken: MlpToken = await deployer.deployOrSkip("MlpToken", "Mlp")
  const pool: LiquidityPool = await deployer.deployUpgradeableOrSkip("LiquidityPool", "LiquidityPool", proxyAdmin)
  const orderBook: OrderBook = await deployer.deployUpgradeableOrSkip("OrderBook", "OrderBook", proxyAdmin)
  const liquidityManager: LiquidityManager = await deployer.deployUpgradeableOrSkip(
    "LiquidityManager",
    "LiquidityManager",
    proxyAdmin
  )
  const reader: Reader = await deployer.deployOrSkip(
    "Reader",
    "Reader",
    pool.address,
    mlpToken.address,
    liquidityManager.address,
    [
      accounts[0].address, // deployer's mux tokens are not debt
    ]
  )

  // init
  console.log("init")
  await ensureFinished(orderBook.initialize(pool.address, mlpToken.address))
  await ensureFinished(orderBook.addBroker(broker))
  await ensureFinished(liquidityManager.initialize(pool.address))
  await ensureFinished(pool.initialize(mlpToken.address))
  await pool.setParams(
    AdminParamsType.SetAddresses,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetAddresses, [orderBook.address, liquidityManager.address])
  )
  await pool.setParams(
    AdminParamsType.SetFundingInterval,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetFundingInterval, [3600 * 8])
  )
  await pool.setParams(
    AdminParamsType.SetLiquidityLockPeriod,
    ethers.utils.defaultAbiCoder.encode(AdminParamsAbi.SetLiquidityLockPeriod, [5 * 60])
  )

  console.log("transfer mlp")
  await ensureFinished(mlpToken.transfer(pool.address, toWei("10000000000000000"))) // < toWei(PreMinedTokenTotalSupply)

  // settings
  await preset1(deployer)
  // await faucet(deployer)
}

restorableEnviron(ENV, main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
