// a simplified version of '@typechain/ethers-v5' where *Factory will not contain bytecode

import { default as TypeChainEthersV5 } from "@typechain/ethers-v5";
import { BytecodeWithLinkReferences, Contract } from "typechain";

export default class Ethers extends TypeChainEthersV5 {
  genContractFactoryFile(contract: Contract, abi: any, bytecode?: BytecodeWithLinkReferences) {
    return super.genContractFactoryFile(contract, abi, undefined);
  }
}
