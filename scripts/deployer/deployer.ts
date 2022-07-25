import * as fs from "fs"
import chalk from "chalk"
import { Signer } from "ethers"
import type { HardhatEthersHelpers } from "@nomiclabs/hardhat-ethers/types"
import { TransactionReceipt } from "@ethersproject/providers"
import { retrieveLinkReferences } from "./linkReferenceParser"

export interface DeploymentOptions {
  network: string
  artifactDirectory: string
  addressOverride: { [key: string]: { [key: string]: string } }
}

export interface DeploymentRecord {
  type: string
  name: string
  address: string
  dependencies?: { admin: string; implementation: string }
  deployedAt?: number
}

export class Deployer {
  public SAVE_PREFIX = "./deployments/"
  public SAVE_POSTFIX = ".deployment.json"

  public e: HardhatEthersHelpers
  public options: DeploymentOptions
  public linkReferences: { [contactName: string]: string[] } = {}
  public deployedContracts: { [aliasName: string]: DeploymentRecord } = {}
  public signer: Signer | null = null

  public beforeDeployed: null | ((contractName: string, factory: any, ...args: any[]) => any) = null
  public afterDeployed: null | ((contractName: string, factory: any, ...args: any[]) => any) = null

  constructor(e: HardhatEthersHelpers, options: DeploymentOptions) {
    this.options = options
    this.e = e
  }

  public async initialize() {
    this.linkReferences = await retrieveLinkReferences(this.options.artifactDirectory)
    this.load()
    for (var contractName in this.options.addressOverride) {
      const contract = this.options.addressOverride[contractName]
      if (!contract.address) {
        throw new Error(`unknown addressOverride[${contractName}].address`)
      }
      this.deployedContracts[contractName] = {
        type: "preset",
        name: contractName,
        ...contract,
        address: contract.address,
      }
    }
  }

  public async finalize() {
    this.save()
  }

  public async load() {
    try {
      const savedProgress = JSON.parse(fs.readFileSync(this.SAVE_PREFIX + this.options.network + this.SAVE_POSTFIX, "utf-8"))
      this.deployedContracts = savedProgress
    } catch (err) {
      this._log("save not found")
    }
  }

  public async save() {
    fs.writeFileSync(this.SAVE_PREFIX + this.options.network + this.SAVE_POSTFIX, JSON.stringify(this.deployedContracts, null, 2))
  }

  public async deployOrSkip(contractName: string, aliasName: string, ...args: any[]): Promise<any> {
    if (!(aliasName in this.deployedContracts)) {
      await this.deploy(contractName, aliasName, ...args)
    }
    return this.getDeployedContract(contractName, aliasName)
  }

  public async deployUpgradeableOrSkip(contractName: string, aliasName: string, admin: string): Promise<any> {
    if (!(aliasName in this.deployedContracts)) {
      await this.deployUpgradeable(contractName, aliasName, admin)
    }
    return this.getDeployedContract(contractName, aliasName)
  }

  public async deploy(contractName: string, aliasName: string, ...args: any[]): Promise<any> {
    const { deployed, receipt } = await this._deploy(contractName, ...args)
    this.deployedContracts[aliasName] = {
      type: "plain",
      name: aliasName,
      address: deployed.address,
      deployedAt: receipt.blockNumber,
    }
    this._logDeployment(aliasName, deployed)
    return deployed
  }

  public async deployUpgradeable(contractName: string, aliasName: string, admin: string): Promise<any> {
    let implementation = await this.deployOrSkip(contractName, contractName + "__implementation")
    const { deployed, receipt } = await this._deploy("TransparentUpgradeableProxy", implementation.address, admin, "0x")
    this.deployedContracts[aliasName] = {
      type: "upgradeable",
      name: aliasName,
      address: deployed.address,
      dependencies: { admin, implementation: implementation.address },
      deployedAt: receipt.blockNumber,
    }
    this._logDeployment(aliasName, deployed, `(implementation[${implementation.address}] admin[${admin}]`)
    return await this.getContractAt(contractName, deployed.address)
  }

  public async upgrade(contractName: string, aliasName: string, admin: string, newImplementation?: string): Promise<any> {
    let proxyAdmin = await this.getContractAt("ProxyAdmin", admin)
    let proxy = this.deployedContracts[aliasName]
    if (!proxy || !proxy.address || proxy.type !== "upgradeable" || !proxy.dependencies) {
      throw new Error(`${aliasName} is not upgradable`)
    }
    let implementation
    if (newImplementation) {
      implementation = { address: newImplementation }
    } else {
      implementation = await this.deploy(contractName, contractName + "__implementation")
    }
    {
      const tx = await proxyAdmin.upgrade(proxy.address, implementation.address)
      await tx.wait()
    }
    proxy.dependencies.implementation = implementation.address
    this._logDeployment(aliasName, proxy, `(implementation[${implementation.address}] admin[${admin}]`)
    return proxy
  }

  public async getDeployedContract(contractName: string, aliasName: string): Promise<any> {
    if (!(aliasName in this.deployedContracts)) {
      throw `${aliasName} has not yet been deployed`
    }
    return this.getContractAt(contractName, this.deployedContracts[aliasName].address)
  }

  public async getContractAt(contractName: string, address: string): Promise<any> {
    const factory = await this.getFactory(contractName)
    return await factory.attach(address)
  }

  public async getFactory(contractName: string): Promise<any> {
    return await this._getFactory(contractName)
  }

  public addressOf(contractName: string) {
    return this.deployedContracts[contractName].address
  }

  public async getImplementation(address: string) {
    const storagePosition = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
    return await this.e.provider.getStorageAt(address, storagePosition)
  }

  public async getBeacon(address: string) {
    const storagePosition = "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50"
    return await this.e.provider.getStorageAt(address, storagePosition)
  }

  public async getAdminOfUpgradableContract(address: string) {
    const storagePosition = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
    return await this.e.provider.getStorageAt(address, storagePosition)
  }

  private async _deploy(contractName: string, ...args: any[]): Promise<any> {
    return this._deployWithSigner(null, contractName, ...args)
  }

  private async _deployWithSigner(signer: Signer | null, contractName: string, ...args: any[]): Promise<{ deployed: any; receipt: TransactionReceipt }> {
    const factory = await this._getFactory(contractName)
    if (this.beforeDeployed != null) {
      await this.beforeDeployed(contractName, factory, ...args)
    }
    let deployed: any
    if (signer == null) {
      deployed = await factory.deploy(...args)
    } else {
      deployed = await factory.connect(signer).deploy(...args)
    }
    const receipt = await deployed.deployTransaction.wait()
    if (this.afterDeployed != null) {
      await this.afterDeployed(contractName, deployed, ...args)
    }
    return { deployed, receipt }
  }

  private async _getFactory(contractName: string): Promise<any> {
    let links: { [contact: string]: string } = {}
    if (contractName in this.linkReferences) {
      for (const linkedContractName of this.linkReferences[contractName]) {
        if (linkedContractName in this.deployedContracts) {
          links[linkedContractName] = this.deployedContracts[linkedContractName].address
        } else {
          const deployed = await this.deploy(linkedContractName, linkedContractName)
          links[linkedContractName] = deployed.address
        }
      }
    }
    return await this.e.getContractFactory(contractName, { libraries: links })
  }

  private _log(...message: any[]) {
    console.log(chalk.underline.bgBlue("Deployer =>"), ...message)
  }

  private _logDeployment(aliasName: string, deployed: DeploymentRecord, message?: string) {
    this._log(`${aliasName} has been deployed to ${deployed.address} ${message || ""}`)
  }
}
