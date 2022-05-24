import hre, { ethers } from "hardhat"
import { restorableEnviron } from "./deployer/environ"
import { toWei, toUnit, toBytes32, rate, ensureFinished, ReferenceOracleType } from "../test/deployUtils"
import { Deployer, DeploymentOptions } from "./deployer/deployer"
import { LiquidityPool, OrderBook, LiquidityManager, Reader, NativeUnwrapper } from "../typechain"
import { MuxToken, MlpToken, MockERC20 } from "../typechain"
import { Contract, ContractReceipt } from "ethers"
import { transferThroughDemoBridge } from "./demoBridgeTransfer"

const TOKEN_POSTFIX = "0328"
const keeperAddress = "0xc6b1458fcc02abc7f3d912fa60c7fb59c957fbf0"

const ENV: DeploymentOptions = {
  network: hre.network.name,
  artifactDirectory: "./artifacts/contracts",
  addressOverride: {
    // ArbRinkeby
    ProxyAdmin: { address: "0x1D34658aD1259F515246335A11372Fe51330999d" },
    WETH9: { address: "0xB47e6A5f8b33b3F17603C83a0535A9dcD7E32681" },
    DemoBridge: { address: "0x505F6EB30251097929c6a89d89F812A270bb098b" },
  },
}

async function faucet(deployer: Deployer) {
  const accounts = await ethers.getSigners()
  console.log("faucet")
  const usdc: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockUsdc", "USD Coin", "USDC", 6) // https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
  const usdt: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockUsdt", "Tether USD", "USDT", 6) // https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7
  const dai: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockDai", "Dai Stablecoin", "DAI", 18) // https://etherscan.io/token/0x6b175474e89094c44da98b954eedeac495271d0f
  const wbtc: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockWbtc", "Wrapped BTC", "WBTC", 8) // https://etherscan.io/token/0x2260fac5e5542a773aa44fbcfedf7c193bc2c599
  const ftm: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockFtm", "Fantom Token", "FTM", 18) // https://etherscan.io/token/0x4e15361fd6b4bb609fa63c81a2be19d873717870
  const link: MockERC20 = await deployer.deployOrSkip("MockERC20", "MockLink", "ChainLink Token", "LINK", 18) // https://etherscan.io/token/0x514910771af9ca656af840dff83e8264ecf986ca
  for (let a of [
    // "0xba893CfA648f46F92a29911589f1A353b6AA4938", // t1
  ]) {
    console.log("to", a)
    await usdc.mint(a, toUnit("200000", 6))
    await usdt.mint(a, toUnit("200000", 6))
    await dai.mint(a, toWei("200000"))
    await wbtc.mint(a, toUnit("4", 8))
    await ftm.mint(a, toWei("200000"))
    await link.mint(a, toWei("10000"))
  }
}

async function preset1(deployer: Deployer) {
  console.log("preset1")
  const accounts = await ethers.getSigners()
  const pool: LiquidityPool = await deployer.getDeployedContract("LiquidityPool", "LiquidityPool")
  const orderBook: OrderBook = await deployer.getDeployedContract("OrderBook", "OrderBook")
  const liquidityManager: LiquidityManager = await deployer.getDeployedContract("LiquidityManager", "LiquidityManager")

  // deploy
  const weth9: MockERC20 = await deployer.getDeployedContract("MockERC20", "WETH9")
  const usdc: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockUsdc")
  const usdt: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockUsdt")
  const dai: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockDai")
  const wbtc: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockWbtc")
  const ftm: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockFtm")
  const link: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockLink")
  const muxUsd: MuxToken = await deployer.getDeployedContract("MuxToken", "MuxUsd")
  const muxWeth: MuxToken = await deployer.getDeployedContract("MuxToken", "MuxWeth")
  const muxWbtc: MuxToken = await deployer.deployOrSkip("MuxToken", "MuxWbtc")
  const muxFtm: MuxToken = await deployer.deployOrSkip("MuxToken", "MuxFtm")
  const muxAvax: MuxToken = await deployer.deployOrSkip("MuxToken", "MuxAvax")
  const muxLink: MuxToken = await deployer.deployOrSkip("MuxToken", "MuxLink")

  console.log("init tokens")
  await muxWbtc.initialize("MUX Token for WBTC", "muxWBTC" + TOKEN_POSTFIX)
  await muxFtm.initialize("MUX Token for FTM", "muxFTM" + TOKEN_POSTFIX)
  await muxAvax.initialize("MUX Token for AVAX", "muxAVAX" + TOKEN_POSTFIX)
  await muxLink.initialize("MUX Token for LINK", "muxLINK" + TOKEN_POSTFIX)

  console.log("transfer mux")
  await muxWbtc.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await muxFtm.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await muxAvax.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await muxLink.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await transferThroughDemoBridge(deployer, accounts[0], 97, muxWbtc.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await transferThroughDemoBridge(deployer, accounts[0], 97, muxFtm.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await transferThroughDemoBridge(deployer, accounts[0], 97, muxAvax.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await transferThroughDemoBridge(deployer, accounts[0], 97, muxLink.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)

  // ----------------------------------------------------------------------------------

  console.log("add stable coins")
  // id, symbol, decimals, stable, token, mux
  await ensureFinished(pool.addAsset(0, toBytes32("USDC"), 6, true, usdc.address, muxUsd.address))
  await ensureFinished(pool.addAsset(1, toBytes32("USDT"), 6, true, usdt.address, muxUsd.address))
  await ensureFinished(pool.addAsset(2, toBytes32("DAI"), 18, true, dai.address, muxUsd.address))
  for (let tokenId = 0; tokenId < 3; tokenId++) {
    console.log("set stable coin", tokenId)

    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(tokenId, rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1)
    // id, tradable, openable, shortable, useStable, enabled, strict
    await pool.setAssetFlags(tokenId, false, false, false, false, true, true)
    await pool.setFundingParams(tokenId, rate("0.00011"), rate("0.0008"))
  }

  // ----------------------------------------------------------------------------------

  console.log("add other coins")
  // id, symbol, decimals, stable, token, mux
  await ensureFinished(pool.addAsset(3, toBytes32("ETH"), 18, false, weth9.address, muxWeth.address))
  await ensureFinished(pool.addAsset(4, toBytes32("BTC"), 8, false, wbtc.address, muxWbtc.address))
  await ensureFinished(pool.addAsset(5, toBytes32("FTM"), 18, false, ftm.address, muxFtm.address))
  await ensureFinished(pool.addAsset(6, toBytes32("AVAX"), 18, false, "0x0000000000000000000000000000000000000000", muxAvax.address))
  await ensureFinished(pool.addAsset(7, toBytes32("LINK"), 18, false, link.address, muxLink.address))
  for (let tokenId = 3; tokenId < 8; tokenId++) {
    console.log("set other coins", tokenId)

    // id, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight
    await pool.setAssetParams(tokenId, rate("0.01"), rate("0.005"), rate("0.001"), rate("0.001"), 60, toWei("1000000"), toWei("1000000"), 2)
    if (tokenId === 6 /* avax */) {
      // id, tradable, openable, shortable, useStable, enabled, strict
      await pool.setAssetFlags(tokenId, true, true, true, true, true, false)
    } else {
      // id, tradable, openable, shortable, useStable, enabled, strict
      await pool.setAssetFlags(tokenId, true, true, true, false, true, false)
    }
    await pool.setFundingParams(tokenId, rate("0.0001"), rate("0.0008"))
  }

  // ----------------------------------------------------------------------------------

  console.log("reference oracle")

  // arbRinkeby
  await pool.setReferenceOracle(3, ReferenceOracleType.Chainlink, "0x5f0423B1a6935dc5596e7A24d98532b67A0AeFd8", rate("0.03")) // ETH
  await pool.setReferenceOracle(4, ReferenceOracleType.Chainlink, "0x0c9973e7a27d00e656B9f153348dA46CaD70d03d", rate("0.03")) // BTC
  await pool.setReferenceOracle(7, ReferenceOracleType.Chainlink, "0x52C9Eb2Cc68555357221CAe1e5f2dD956bC194E5", rate("0.03")) // LINK

  // ----------------------------------------------------------------------------------

  // console.log("add dex - weth-usdc")
  // await liquidityManager.addDexSpotConfiguration("MockUniswap2", 3, [0, 3], [4, 5])
}

async function addLiq(deployer: Deployer) {
  const accounts = await ethers.getSigners()
  const lp1 = accounts[2]

  const pool: LiquidityPool = await deployer.getDeployedContract("LiquidityPool", "LiquidityPool")
  const orderBook: OrderBook = await deployer.getDeployedContract("OrderBook", "OrderBook")
  const liquidityManager: LiquidityManager = await deployer.getDeployedContract("LiquidityManager", "LiquidityManager")

  // deploy
  const weth9: MockERC20 = await deployer.getDeployedContract("MockERC20", "WETH9")
  const usdc: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockUsdc")
  const usdt: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockUsdt")
  const dai: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockDai")
  const wbtc: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockWbtc")
  const ftm: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockFtm")
  const link: MockERC20 = await deployer.getDeployedContract("MockERC20", "MockLink")
  const muxUsd: MuxToken = await deployer.getDeployedContract("MuxToken", "MuxUsd")
  const muxWeth: MuxToken = await deployer.getDeployedContract("MuxToken", "MuxWeth")
  const muxWbtc: MuxToken = await deployer.getDeployedContract("MuxToken", "MuxWbtc")
  const muxFtm: MuxToken = await deployer.getDeployedContract("MuxToken", "MuxFtm")
  const muxAvax: MuxToken = await deployer.getDeployedContract("MuxToken", "MuxAvax")
  const muxLink: MuxToken = await deployer.getDeployedContract("MuxToken", "MuxLink")

  console.log("temporarily close liquidity lock (test only)")
  await orderBook.setLiquidityLockPeriod(0)

  // ----------------------------------------------------------------------------------

  console.log("add liquidity - usd")
  await usdc.mint(lp1.address, toUnit("1000000", 6)) // faucet
  await usdt.mint(lp1.address, toUnit("1000000", 6)) // faucet
  await dai.mint(lp1.address, toWei("1000000")) // faucet
  await ensureFinished(usdc.connect(accounts[2]).approve(orderBook.address, toUnit("1000000", 6)))
  await ensureFinished(usdt.connect(accounts[2]).approve(orderBook.address, toUnit("1000000", 6)))
  await ensureFinished(dai.connect(accounts[2]).approve(orderBook.address, toWei("1000000")))
  {
    const tx1 = (await ensureFinished(orderBook.connect(accounts[2]).placeLiquidityOrder(0, toUnit("1000000", 6), true))) as ContractReceipt
    const orderId = getOrderId(tx1)
    await ensureFinished(orderBook.connect(accounts[1]).fillLiquidityOrder(orderId, toWei("1"), toWei("1"), toWei("0"), toWei("0")))
  }
  {
    const tx1 = (await ensureFinished(orderBook.connect(accounts[2]).placeLiquidityOrder(1, toUnit("1000000", 6), true))) as ContractReceipt
    const orderId = getOrderId(tx1)
    await ensureFinished(orderBook.connect(accounts[1]).fillLiquidityOrder(orderId, toWei("1"), toWei("1"), toWei("0"), toWei("0")))
  }
  {
    const tx1 = (await ensureFinished(orderBook.connect(accounts[2]).placeLiquidityOrder(2, toWei("1000000"), true))) as ContractReceipt
    const orderId = getOrderId(tx1)
    await ensureFinished(orderBook.connect(accounts[1]).fillLiquidityOrder(orderId, toWei("1"), toWei("1"), toWei("0"), toWei("0")))
  }

  console.log("add liquidity - btc")
  await wbtc.mint(lp1.address, toUnit("200", 8)) // faucet
  await ensureFinished(wbtc.connect(accounts[2]).approve(orderBook.address, toUnit("200", 8)))
  {
    const tx1 = (await ensureFinished(orderBook.connect(accounts[2]).placeLiquidityOrder(4, toUnit("200", 8), true))) as ContractReceipt
    const orderId = getOrderId(tx1)
    await ensureFinished(orderBook.connect(accounts[1]).fillLiquidityOrder(orderId, toWei("40000"), toWei("1"), toWei("0"), toWei("0")))
  }

  // ----------------------------------------------------------------------------------

  console.log("add liquidity through bridge")
  await usdc.mint(lp1.address, toUnit("1000000", 6)) // faucet
  await wbtc.mint(lp1.address, toUnit("20", 8)) // faucet
  await transferThroughDemoBridge(deployer, lp1, 97, usdc.address, toUnit("1000000", 6))
  await transferThroughDemoBridge(deployer, lp1, 97, wbtc.address, toUnit("20", 8)) // < toWei(PreMinedTokenTotalSupply)

  // ----------------------------------------------------------------------------------

  console.log("recovery liquidity lock (test only)")
  await orderBook.setLiquidityLockPeriod(5 * 60)
}

function getOrderId(receipt: ContractReceipt): string {
  let orderId = "0"
  for (let event of receipt.events!) {
    if (event.event === "NewLiquidityOrder") {
      orderId = event.args!.orderId.toString()
      console.log("orderId:", orderId)
    }
  }
  return orderId
}

async function main(deployer: Deployer) {
  const accounts = await ethers.getSigners()
  if (accounts.length < 3) {
    throw new Error("this script needs 3 accounts: deployer/vault, broker, lp")
  }
  const vault = accounts[0]

  // deploy
  let proxyAdmin = deployer.addressOf("ProxyAdmin")
  const weth9: MockERC20 = await deployer.getDeployedContract("MockERC20", "WETH9")
  const mlpToken: MlpToken = await deployer.deployUpgradeableOrSkip("MlpToken", "Mlp", proxyAdmin)
  await deployer.deployUpgradeableOrSkip("LiquidityPoolHop1", "LiquidityPool", proxyAdmin)
  const poolHop2: Contract = await deployer.deployOrSkip("LiquidityPoolHop2", "LiquidityPoolHop2")
  const pool: LiquidityPool = await deployer.getDeployedContract("LiquidityPool", "LiquidityPool")
  const orderBook: OrderBook = await deployer.deployUpgradeableOrSkip("OrderBook", "OrderBook", proxyAdmin)
  await deployer.deployUpgradeableOrSkip("LiquidityManager", "LiquidityManager", proxyAdmin)
  const liquidityManager = await deployer.getDeployedContract("LiquidityManager", "LiquidityManager")
  const dexLiquidity = await deployer.deployOrSkip("DexLiquidity", "DexLiquidity", liquidityManager.address)
  const reader: Reader = await deployer.deployOrSkip("Reader", "Reader", pool.address, mlpToken.address, dexLiquidity.address, orderBook.address, [
    accounts[0].address, // deployer's mux tokens are not debt
  ])
  const nativeUnwrapper: NativeUnwrapper = await deployer.deployOrSkip("NativeUnwrapper", "NativeUnwrapper", weth9.address)
  const muxUsd: MuxToken = await deployer.deployOrSkip("MuxToken", "MuxUsd")
  const muxWeth: MuxToken = await deployer.deployOrSkip("MuxToken", "MuxWeth")

  // init
  console.log("init")
  await ensureFinished(mlpToken.initialize("MUX LP", "MUXLP" + TOKEN_POSTFIX))
  await ensureFinished(muxUsd.initialize("MUX Token for USD", "muxUSD" + TOKEN_POSTFIX))
  await ensureFinished(muxWeth.initialize("MUX Token for WETH", "muxWETH" + TOKEN_POSTFIX))
  await ensureFinished(pool.initialize(poolHop2.address, mlpToken.address, orderBook.address, liquidityManager.address, weth9.address, nativeUnwrapper.address))
  await ensureFinished(orderBook.initialize(pool.address, mlpToken.address, weth9.address, nativeUnwrapper.address))
  await orderBook.addBroker(accounts[1].address)
  await orderBook.addBroker(keeperAddress)
  await orderBook.setLiquidityLockPeriod(5 * 60)
  await ensureFinished(liquidityManager.initialize(vault.address, pool.address))
  // fundingInterval, mlpPrice, mlpPrice, liqBase, liqDyn
  await pool.setNumbers(3600 * 8, toWei("0.9"), toWei("1.1"), rate("0.0025"), rate("0.005"))
  await liquidityManager.addExternalAccessor(dexLiquidity.address)
  await ensureFinished(nativeUnwrapper.addWhiteList(pool.address))
  await ensureFinished(nativeUnwrapper.addWhiteList(orderBook.address))

  console.log("transfer mlp")
  await mlpToken.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await transferThroughDemoBridge(deployer, accounts[0], 97, mlpToken.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)

  console.log("transfer muxUsd")
  await muxUsd.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await muxWeth.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await transferThroughDemoBridge(deployer, accounts[0], 97, muxUsd.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await transferThroughDemoBridge(deployer, accounts[0], 97, muxWeth.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)

  // presets
  await faucet(deployer)
  await preset1(deployer)
  await addLiq(deployer)
}

restorableEnviron(ENV, main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
