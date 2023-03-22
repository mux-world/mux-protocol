import { ethers } from "hardhat"
import { Deployer, DeploymentOptions } from "./deployer"
import { printError } from "../../test/deployUtils"

export async function restorableEnviron(
  options: DeploymentOptions,
  job: (deployer: Deployer, ...args: any[]) => Promise<any>,
  ...args: any
) {
  // detect network
  const deployer = new Deployer(ethers, options)
  await deployer.initialize()
  // main logic
  try {
    await job(deployer, ...args)
  } catch (err) {
    printError("Error occurs:", err)
  } finally {
    // save deployed
    deployer.finalize()
  }
}

export async function readOnlyEnviron(
  options: DeploymentOptions,
  job: (deployer: Deployer, ...args: any[]) => Promise<any>,
  ...args: any
) {
  // detect network
  const deployer = new Deployer(ethers, options)
  await deployer.initialize()
  // main logic
  await job(deployer, ...args)
}
