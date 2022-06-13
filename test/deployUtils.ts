import { ethers } from "hardhat"
import { BytesLike, ContractTransaction, Contract, ContractReceipt } from "ethers"
import { hexlify, concat, zeroPad, arrayify } from "@ethersproject/bytes"
import { TransactionReceipt } from "@ethersproject/providers"
import { BigNumber, BigNumberish, parseFixed, formatFixed } from "@ethersproject/bignumber"
const chalk = require("chalk")

export enum OrderType {
  Invalid,
  Position,
  Liquidity,
  Withdrawal,
  Rebalance,
}

export enum PositionOrderFlags {
  OpenPosition = 0x80, // 0x80 means openPosition; otherwise closePosition
  MarketOrder = 0x40, // 0x40 means ignore limitPrice
  WithdrawAllIfEmpty = 0x20, // 0x20 means auto withdraw all collateral if position.size == 0
  TriggerOrder = 0x10, // 0x10 means this is a trigger order (ex: stop-loss order). 0 means this is a limit order (ex: take-profit order)
}

export enum ReferenceOracleType {
  None,
  Chainlink,
}

// do not forget toWei(PreMinedTokenTotalSupply)
export const PreMinedTokenTotalSupply = "1000000000000000000"

export function printInfo(...message: any[]) {
  console.log(chalk.yellow("INF "), ...message)
}

export function printError(...message: any[]) {
  console.log(chalk.red("ERR "), ...message)
}

export function toWei(n: string): BigNumber {
  return ethers.utils.parseEther(n)
}

export function fromWei(n: BigNumberish): string {
  return ethers.utils.formatEther(n)
}

export function toUnit(n: string, decimals: number): BigNumber {
  return parseFixed(n, decimals)
}

export function fromUnit(n: BigNumberish, decimals: number): string {
  return formatFixed(n, decimals)
}

export function toBytes32(s: string): string {
  return ethers.utils.formatBytes32String(s)
}

export function fromBytes32(s: BytesLike): string {
  return ethers.utils.parseBytes32String(s)
}

export function rate(n: string): BigNumber {
  return toUnit(n, 5)
}

export function toChainlink(n: string): BigNumber {
  return toUnit(n, 8)
}

export async function createFactory(path: any, libraries: { [name: string]: { address: string } } = {}): Promise<any> {
  const parsed: { [name: string]: string } = {}
  for (var name in libraries) {
    parsed[name] = libraries[name].address
  }
  return await ethers.getContractFactory(path, { libraries: parsed })
}

export async function createContract(path: any, args: any = [], libraries: { [name: string]: { address: string } } = {}): Promise<Contract> {
  const factory = await createFactory(path, libraries)
  return await factory.deploy(...args)
}

export function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export async function ensureFinished(transaction: Promise<Contract> | Promise<ContractTransaction>): Promise<TransactionReceipt | ContractReceipt> {
  const result: Contract | ContractTransaction = await transaction
  let receipt: TransactionReceipt | ContractReceipt
  if ((result as Contract).deployTransaction) {
    receipt = await (result as Contract).deployTransaction.wait()
  } else {
    receipt = await result.wait()
  }
  if (receipt.status !== 1) {
    throw new Error(`receipt err: ${receipt.transactionHash}`)
  }
  return receipt
}

export function hashString(x: string): Buffer {
  return hash(ethers.utils.toUtf8Bytes(x))
}

export function hash(x: BytesLike): Buffer {
  return Buffer.from(ethers.utils.keccak256(x).slice(2), "hex")
}

export function padAccount(account: string): Buffer {
  return Buffer.from(account.slice(2).padStart(64, "0"), "hex")
}

export function assembleSubAccountId(account: string, collateral: number, asset: number, isLong: boolean): string {
  return hexlify(
    concat([
      arrayify(account),
      [arrayify(BigNumber.from(collateral))[0]],
      [arrayify(BigNumber.from(asset))[0]],
      arrayify(BigNumber.from(isLong ? 1 : 0)),
      zeroPad([], 9),
    ])
  )
}
