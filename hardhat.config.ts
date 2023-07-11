import { task } from "hardhat/config"
import "@typechain/hardhat"
import "@nomiclabs/hardhat-ethers"
import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-etherscan"
//import "solidity-coverage"
//import "hardhat-gas-reporter"
import { retrieveLinkReferences } from "./scripts/deployer/linkReferenceParser"

const etherscanApiKey = process.env["ETHERSCAN_API_KEY"]

task("deploy", "Deploy a single contract")
  .addPositionalParam("name", "Name of contract to deploy")
  .addOptionalPositionalParam("args", "Args of contract constructor, separated by common ','")
  .setAction(async (args, hre) => {
    if (typeof args.args != "undefined") {
      args.args = args.args.split(",")
    }
    let nonce = await hre.ethers.provider.getTransactionCount(
      await hre.ethers.provider.getSigner(0).getAddress(),
      "pending"
    )
    console.log("nonce", nonce)
    const linkReferences = await retrieveLinkReferences("./artifacts/contracts")
    const links: { [contactName: string]: string } = {}
    const go = async (contractName: string) => {
      const innerLinks: { [contactName: string]: string } = {}
      for (let linkedContractName of linkReferences[contractName] || []) {
        if (linkedContractName in links) {
          innerLinks[linkedContractName] = links[linkedContractName]
        } else {
          const deployed = await go(linkedContractName)
          innerLinks[linkedContractName] = deployed
          links[linkedContractName] = deployed
        }
      }
      const factory = await hre.ethers.getContractFactory(contractName, { libraries: innerLinks })
      const constructArgs = args.args ? args.args : []
      console.log("deploying", contractName, "links:", innerLinks, "ctor:", constructArgs, "nonce:", nonce)
      constructArgs.push({ nonce: nonce++ })
      const deployed = await factory.deploy(...constructArgs)
      console.log(contractName, "deployed at", deployed.address)
      await deployed.deployTransaction.wait()
      return deployed.address
    }
    await go(args.name)
  })

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    arb1: {
      url: `https://arb1.arbitrum.io/rpc`,
      gasPrice: 2e9,
      blockGasLimit: "80000000",
      accounts: [],
    },
    arbrinkeby: {
      url: `https://rinkeby.arbitrum.io/rpc`,
      // gasPrice: 5e9,
      blockGasLimit: "80000000",
      accounts: [],
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.4.18",
        settings: {
          optimizer: {
            enabled: false, // see https://bscscan.com/address/0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c
            runs: 200,
          },
        },
      },
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  etherscan: {
    apiKey: etherscanApiKey,
  },
  mocha: {
    timeout: 60000,
  },
  gasReporter: {
    currency: "ETH",
    gasPrice: 100,
  },
  typechain: {
    outDir: "typechain",
    target: "./misc/typechain-ethers-v5-mux",
  },
}
