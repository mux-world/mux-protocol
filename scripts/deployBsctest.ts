import hre, { ethers } from "hardhat"
import { restorableEnviron } from "./deployer/environ"
import { toWei, toUnit, toBytes32, rate, ensureFinished, ReferenceOracleType } from "../test/deployUtils"
import { Deployer, DeploymentOptions } from "./deployer/deployer"
import { LiquidityPool, OrderBook, LiquidityManager, Reader, NativeUnwrapper } from "../typechain"
import { MuxToken, MlpToken, MockERC20 } from "../typechain"
import { Contract, ContractReceipt } from "ethers"
import { Vault } from "../typechain/Vault"

const keeperAddress = "0xc6b1458fcc02abc7f3d912fa60c7fb59c957fbf0"

const CHAIN_ID = {
  arbRinkeby: 421611,
  fantomTestnet: 0xfa2,
  bscTestnet: 0x61,
  avalancheTestnet: 43113,
}

const ENV: DeploymentOptions = {
  network: hre.network.name,
  artifactDirectory: "./artifacts/contracts",
  addressOverride: {
    // bscTestnet
    // ProxyAdmin: { address: "0x50019d8b00eaaac9bd5f0c79a1ebce6594cf1bba" },
    // WrappedNative: { address: "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd" },
    // DemoBridge: { address: "0x108E20E678956cf90CD9cD009371cc11433e181E" },
    // PeggedUsdc: { address: "0xB742302463F9D3AB853ddedBc41D5dcE84B3A354" },
    // PeggedUsdt: { address: "0x0d59DA268eb2f0b69e896f5506Ada6320A8E5B0E" },
    // PeggedDai: { address: "0x8eEb4bAD711d8513513fAFcf41f5FED0efEAd097" },
    // PeggedWeth: { address: "0xd569Ae3Be614DE18aBF1B9b1BE664B3CF899830e" },
    // PeggedWbtc: { address: "0x981306FE3749e98661e190522099717AcE1D95B0" },
    // PeggedLink: { address: "0x5905b650fCFE12f2d7979651A8AdeB9Dde39Cc91" },
    // PeggedMlp: { address: "0x0F97336F83DB38E0D8B7324F37703e6216C533De" },
    // PeggedMuxUsd: { address: "0x20Fb9584d68Ce8CD7e59092B3E046c5175C1ce76" },
    // PeggedMuxWeth: { address: "0xeB1b1D630b48e8539316e5247941D40904e050dB" },
    // PeggedMuxWbtc: { address: "0x8C62ad34A7EC8ccE177A397c9AD31D1fE70a4A54" },
    // PeggedMuxFtm: { address: "0xfB5756B8bB7c53628A096ED77303Fd5da4ab782f" },
    // PeggedMuxAvax: { address: "0x30aAa26DD30ED56Ef992Dc463B73365dEb6cd2cd" },
    // PeggedMuxLink: { address: "0x9f72E680404Cc24Afb342D5e4e5E7D402011D69d" },
    // fantomTestnet
    // ProxyAdmin: { address: "0x49586C43Fc7A905dc7Bbeb99de9Ab108B8557531" },
    // WrappedNative: { address: "0xf1277d1ed8ad466beddf92ef448a132661956621" },
    // DemoBridge: { address: "0x55d5F6248eD6bD6a558E1DA860d050e151857C1c" },
    // PeggedUsdc: { address: "0xF2B2d1A4a225062D184ec25a736a607734bDfBdd" },
    // PeggedUsdt: { address: "0xB742302463F9D3AB853ddedBc41D5dcE84B3A354" },
    // PeggedDai: { address: "0x894c477b20055fF1a2DA571aeBEA7572385A0FF9" },
    // PeggedWeth: { address: "0x30aAa26DD30ED56Ef992Dc463B73365dEb6cd2cd" },
    // PeggedWbtc: { address: "0x62A2ecF53B912FBBf87e07345Ab2dd1b8112E635" },
    // PeggedLink: { address: "0x981306FE3749e98661e190522099717AcE1D95B0" },
    // PeggedMlp: { address: "0xF65976b7a02bd986DbBc5fcA1881633F5665ff99" },
    // PeggedMuxUsd: { address: "0x5905b650fCFE12f2d7979651A8AdeB9Dde39Cc91" },
    // PeggedMuxWeth: { address: "0x0F97336F83DB38E0D8B7324F37703e6216C533De" },
    // PeggedMuxWbtc: { address: "0x20Fb9584d68Ce8CD7e59092B3E046c5175C1ce76" },
    // PeggedMuxFtm: { address: "0xeB1b1D630b48e8539316e5247941D40904e050dB" },
    // PeggedMuxAvax: { address: "0x8C62ad34A7EC8ccE177A397c9AD31D1fE70a4A54" },
    // PeggedMuxLink: { address: "0xfB5756B8bB7c53628A096ED77303Fd5da4ab782f" },
    // avalancheTestnet
    // ProxyAdmin: { address: "0x6555942f029E6Fa05c37691E7212c0bcc9a56A9D" },
    // WrappedNative: { address: "0xd00ae08403B9bbb9124bB305C09058E32C39A48c" },
    // DemoBridge: { address: "0x1D34658aD1259F515246335A11372Fe51330999d" },
    // PeggedUsdc: { address: "0x50019D8B00EaAAc9bd5F0C79A1EbCe6594Cf1bbA" },
    // PeggedUsdt: { address: "0x879FeF0e0c46d61884977ac6B8c8e37fBA087673" },
    // PeggedDai: { address: "0xd037289cd24c328d53D6115cff63Ed6414F57a6A" },
    // PeggedWeth: { address: "0xFC6d57Ec2715BC57D6D82133F0F063778923BCA7" },
    // PeggedWbtc: { address: "0x547FaBf704469f73ffa6AFF44d311f5586bFE5D5" },
    // PeggedLink: { address: "0x13f9A02F8fA01528F603269A52D64fBAaD3b3351" },
    // PeggedMlp: { address: "0x9229bb4403113c26EE8AcAcAD2fEcB6a2a83D514" },
    // PeggedMuxUsd: { address: "0x614388aa2612cB9A476C34c2343f136927CE3dbd" },
    // PeggedMuxWeth: { address: "0x36475Bc5Ba7988A0d65e739A37d24Dd3D34d1399" },
    // PeggedMuxWbtc: { address: "0x19b306373e29A9d41c761B2373E8968E9b72EddF" },
    // PeggedMuxFtm: { address: "0x66025eF9432D20D108E4F0276e849233Fc1C7c66" },
    // PeggedMuxAvax: { address: "0x5263b562875309690903649bF3E5B9fE92750D85" },
    // PeggedMuxLink: { address: "0x06e31a2BD28580C48130a8CFAc462FC0Ea363cc9" },
  },
}

async function preset1(deployer: Deployer) {
  console.log("preset1")
  const accounts = await ethers.getSigners()
  const pool: LiquidityPool = await deployer.getDeployedContract("LiquidityPool", "LiquidityPool")
  const orderBook: OrderBook = await deployer.getDeployedContract("OrderBook", "OrderBook")
  const liquidityManager: LiquidityManager = await deployer.getDeployedContract("LiquidityManager", "LiquidityManager")

  // deploy
  const usdc: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedUsdc")
  const usdt: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedUsdt")
  const dai: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedDai")
  const weth: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedWeth")
  const wbtc: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedWbtc")
  const link: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedLink")
  const muxUsd: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxUsd")
  const muxWeth: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxWeth")
  const muxWbtc: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxWbtc")
  const muxFtm: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxFtm")
  const muxAvax: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxAvax")
  const muxLink: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxLink")

  console.log("transfer mux")
  await muxWeth.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await muxWbtc.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await muxFtm.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await muxAvax.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)
  await muxLink.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)

  // ----------------------------------------------------------------------------------

  console.log("add stable coins")
  // id, symbol, decimals, stable, token, mux
  await ensureFinished(pool.addAsset(0, toBytes32("USDC"), 6, true, usdc.address, muxUsd.address))
  await ensureFinished(pool.addAsset(1, toBytes32("USDT"), 6, true, usdt.address, muxUsd.address))
  await ensureFinished(pool.addAsset(2, toBytes32("DAI"), 18, true, dai.address, muxUsd.address))
  // id, symbol, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, halfSpread
  await pool.setAssetParams(0, toBytes32("USDC"), rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1, rate("0"))
  await pool.setAssetParams(1, toBytes32("USDT"), rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1, rate("0"))
  await pool.setAssetParams(2, toBytes32("DAI"), rate("0"), rate("0"), rate("0"), rate("0"), 0, toWei("0"), toWei("0"), 1, rate("0"))
  for (let tokenId = 0; tokenId < 3; tokenId++) {
    console.log("set stable coin", tokenId)

    // id, tradable, openable, shortable, useStable, enabled, strict, liq
    await pool.setAssetFlags(tokenId, false, false, false, false, true, true, true)
    await pool.setFundingParams(tokenId, rate("0.00011"), rate("0.0008"))
  }

  // ----------------------------------------------------------------------------------

  console.log("add other coins")
  // id, symbol, decimals, stable, token, mux
  await ensureFinished(pool.addAsset(3, toBytes32("ETH"), 18, false, weth.address, muxWeth.address))
  if ((await ethers.provider.getNetwork()).chainId === CHAIN_ID.bscTestnet || (await ethers.provider.getNetwork()).chainId === CHAIN_ID.fantomTestnet) {
    await ensureFinished(pool.addAsset(4, toBytes32("BTC"), 18 /* CAUTION: BSC, fantom only */, false, wbtc.address, muxWbtc.address))
  } else {
    await ensureFinished(pool.addAsset(4, toBytes32("BTC"), 8, false, wbtc.address, muxWbtc.address))
  }
  if ((await ethers.provider.getNetwork()).chainId === CHAIN_ID.fantomTestnet) {
    await ensureFinished(pool.addAsset(5, toBytes32("FTM"), 18, false, "0xf1277d1Ed8AD466beddF92ef448A132661956621" /* CAUTION: FTM only */, muxFtm.address))
  } else {
    await ensureFinished(pool.addAsset(5, toBytes32("FTM"), 18, false, "0x0000000000000000000000000000000000000000", muxFtm.address))
  }
  if ((await ethers.provider.getNetwork()).chainId === CHAIN_ID.avalancheTestnet) {
    await ensureFinished(pool.addAsset(6, toBytes32("AVAX"), 18, false, "0xd00ae08403B9bbb9124bB305C09058E32C39A48c" /* CAUTION: Avalanche only */, muxAvax.address))
  } else {
    await ensureFinished(pool.addAsset(6, toBytes32("AVAX"), 18, false, "0x0000000000000000000000000000000000000000", muxAvax.address))
  }
  await ensureFinished(pool.addAsset(7, toBytes32("LINK"), 18, false, link.address, muxLink.address))
  await pool.setAssetParams(3, toBytes32("ETH"), rate("0.01"), rate("0.005"), rate("0.001"), rate("0.001"), 60, toWei("1000000"), toWei("1000000"), 2, rate("0"))
  await pool.setAssetParams(4, toBytes32("BTC"), rate("0.01"), rate("0.005"), rate("0.001"), rate("0.001"), 60, toWei("1000000"), toWei("1000000"), 2, rate("0"))
  await pool.setAssetParams(5, toBytes32("FTM"), rate("0.01"), rate("0.005"), rate("0.001"), rate("0.001"), 60, toWei("1000000"), toWei("1000000"), 2, rate("0.0012"))
  await pool.setAssetParams(6, toBytes32("AVAX"), rate("0.01"), rate("0.005"), rate("0.001"), rate("0.001"), 60, toWei("1000000"), toWei("1000000"), 2, rate("0.0012"))
  await pool.setAssetParams(7, toBytes32("LINK"), rate("0.01"), rate("0.005"), rate("0.001"), rate("0.001"), 60, toWei("1000000"), toWei("1000000"), 2, rate("0"))
  // id, symbol, imr, mmr, fee, minBps, minTime, maxLong, maxShort, spotWeight, halfSpread
  for (let tokenId = 3; tokenId < 8; tokenId++) {
    console.log("set other coins", tokenId)

    let useStable = false
    let canBeLiq = true
    if (tokenId === 5 /* ftm */) {
      if ((await ethers.provider.getNetwork()).chainId !== CHAIN_ID.fantomTestnet) {
        useStable = true
        canBeLiq = false
      }
    } else if (tokenId === 6 /* avax */) {
      if ((await ethers.provider.getNetwork()).chainId !== CHAIN_ID.avalancheTestnet) {
        useStable = true
        canBeLiq = false
      }
    }
    // id, tradable, openable, shortable, useStable, enabled, strict, liq
    await pool.setAssetFlags(tokenId, true, true, true, useStable, true, false, canBeLiq)

    await pool.setFundingParams(tokenId, rate("0.0001"), rate("0.0008"))
  }

  // ----------------------------------------------------------------------------------

  console.log("reference oracle")

  // bsc
  await pool.setReferenceOracle(3, ReferenceOracleType.Chainlink, "0x143db3CEEfbdfe5631aDD3E50f7614B6ba708BA7", rate("0.03")) // ETH
  await pool.setReferenceOracle(4, ReferenceOracleType.Chainlink, "0x5741306c21795FdCBb9b265Ea0255F499DFe515C", rate("0.03")) // BTC
  await pool.setReferenceOracle(7, ReferenceOracleType.Chainlink, "0x1B329402Cb1825C6F30A0d92aB9E2862BE47333f", rate("0.03")) // LINK
}

async function addLiq(deployer: Deployer) {
  const accounts = await ethers.getSigners()
  const lp1 = accounts[2]

  const pool: LiquidityPool = await deployer.getDeployedContract("LiquidityPool", "LiquidityPool")
  const orderBook: OrderBook = await deployer.getDeployedContract("OrderBook", "OrderBook")
  const liquidityManager: LiquidityManager = await deployer.getDeployedContract("LiquidityManager", "LiquidityManager")

  // deploy
  const usdc: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedUsdc")
  const usdt: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedUsdt")
  const dai: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedDai")
  const weth: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedWeth")
  const wbtc: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedWbtc")
  const link: MockERC20 = await deployer.getDeployedContract("MockERC20", "PeggedLink")
  const muxUsd: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxUsd")
  const muxWeth: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxWeth")
  const muxWbtc: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxWbtc")
  const muxFtm: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxFtm")
  const muxAvax: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxAvax")
  const muxLink: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxLink")

  console.log("temporarily close liquidity lock (test only)")
  await orderBook.setLiquidityLockPeriod(0)

  // ----------------------------------------------------------------------------------

  console.log("add liquidity - usd")
  await ensureFinished(usdc.connect(accounts[2]).approve(orderBook.address, toUnit("1000000", 6)))
  {
    const tx1 = (await ensureFinished(orderBook.connect(accounts[2]).placeLiquidityOrder(0, toUnit("1000000", 6), true))) as ContractReceipt
    const orderId = getOrderId(tx1)
    await ensureFinished(orderBook.connect(accounts[1]).fillLiquidityOrder(orderId, toWei("1"), toWei("1"), toWei("0"), toWei("0")))
  }

  console.log("add liquidity - btc")
  if ((await ethers.provider.getNetwork()).chainId === CHAIN_ID.bscTestnet) {
    await ensureFinished(wbtc.connect(accounts[2]).approve(orderBook.address, toUnit("20", 18 /* CAUTION: BSC only */)))
    {
      const tx1 = (await ensureFinished(orderBook.connect(accounts[2]).placeLiquidityOrder(4, toUnit("20", 18 /* CAUTION: BSC only */), true))) as ContractReceipt
      const orderId = getOrderId(tx1)
      await ensureFinished(orderBook.connect(accounts[1]).fillLiquidityOrder(orderId, toWei("40000"), toWei("1"), toWei("0"), toWei("0")))
    }
  }

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
    throw new Error("this script needs 3 accounts: deployer, broker, lp")
  }

  // deploy
  let proxyAdmin = deployer.addressOf("ProxyAdmin")
  const wNative: MockERC20 = await deployer.getDeployedContract("MockERC20", "WrappedNative")
  const mlpToken: MlpToken = await deployer.getDeployedContract("MockERC20", "PeggedMlp")
  await deployer.deployUpgradeableOrSkip("LiquidityPoolHop1", "LiquidityPool", proxyAdmin)
  const poolHop2: Contract = await deployer.deployOrSkip("LiquidityPoolHop2", "LiquidityPoolHop2")
  const pool: LiquidityPool = await deployer.getDeployedContract("LiquidityPool", "LiquidityPool")
  const orderBook: OrderBook = await deployer.deployUpgradeableOrSkip("OrderBook", "OrderBook", proxyAdmin)
  await deployer.deployUpgradeableOrSkip("LiquidityManager", "LiquidityManager", proxyAdmin)
  const liquidityManager = await deployer.getDeployedContract("LiquidityManager", "LiquidityManager")
  const reader: Reader = await deployer.deployOrSkip("Reader", "Reader", pool.address, mlpToken.address, liquidityManager.address, orderBook.address, [
    accounts[0].address, // deployer's mux tokens are not debt
  ])
  const nativeUnwrapper: NativeUnwrapper = await deployer.deployOrSkip("NativeUnwrapper", "NativeUnwrapper", wNative.address)
  const vault: Vault = await deployer.deployUpgradeableOrSkip("Vault", "Vault", proxyAdmin)
  const muxUsd: MuxToken = await deployer.getDeployedContract("MockERC20", "PeggedMuxUsd")

  // init
  console.log("init")
  await ensureFinished(pool.initialize(poolHop2.address, mlpToken.address, orderBook.address, liquidityManager.address, wNative.address, nativeUnwrapper.address, vault.address))
  await ensureFinished(orderBook.initialize(pool.address, mlpToken.address, wNative.address, nativeUnwrapper.address))
  await orderBook.addBroker(accounts[1].address)
  await orderBook.addBroker(keeperAddress)
  await orderBook.setLiquidityLockPeriod(5 * 60)
  await orderBook.setOrderTimeout(300, 86400 * 365)
  await ensureFinished(liquidityManager.initialize(vault.address, pool.address))
  // fundingInterval, liqBase, liqDyn, σ_strict, brokerGas
  await pool.setNumbers(3600 * 8, rate("0.0025"), rate("0.005"), rate("0.01"), toWei("0"))
  // mlpPrice, mlpPrice
  await pool.setEmergencyNumbers(toWei("0.5"), toWei("1.1"))
  await ensureFinished(nativeUnwrapper.addWhiteList(pool.address))
  await ensureFinished(nativeUnwrapper.addWhiteList(orderBook.address))
  await ensureFinished(vault.initialize())

  console.log("transfer mlp")
  await mlpToken.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)

  console.log("transfer muxUsd")
  await muxUsd.transfer(pool.address, toWei("10000000000000000")) // < toWei(PreMinedTokenTotalSupply)

  // settings
  await preset1(deployer)
  await addLiq(deployer)
}

restorableEnviron(ENV, main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
