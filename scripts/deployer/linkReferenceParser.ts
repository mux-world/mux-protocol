import * as fs from "fs"
import * as path from "path"

export async function retrieveFiles(directory: string, excludes?: string, includes?: string): Promise<string[]> {
  async function _retrieveFiles(directory: string, results: string[], excludesReg?: RegExp, includesReg?: RegExp) {
    let currentFiles = await fs.readdirSync(directory)
    currentFiles.forEach((file) => {
      const state = fs.statSync(path.join(directory, file))
      const fullPath = directory + "/" + file
      if (state.isDirectory()) {
        _retrieveFiles(fullPath, results, excludesReg, includesReg)
      } else {
        if (excludesReg && excludesReg.test(fullPath)) {
          return
        }
        if (includesReg && !includesReg.test(fullPath)) {
          return
        }
        results.push(fullPath)
      }
    })
  }

  let files: string[] = []
  let excludesReg = excludes ? new RegExp(excludes) : undefined
  let includesReg = includes ? new RegExp(includes) : undefined
  await _retrieveFiles(directory, files, excludesReg, includesReg)
  return files
}

export async function parseLinkedLibraries(filePaths: fs.PathLike[]): Promise<{ [contact: string]: string[] }> {
  let result: { [contact: string]: string[] } = {}
  for (let i = 0; i < filePaths.length; i++) {
    try {
      const rawContent = fs.readFileSync(filePaths[i], "utf-8")
      const jsonContent = JSON.parse(rawContent)
      const contractName = jsonContent.contractName
      const linkReferences = jsonContent.linkReferences
      let referencesContractNames = []
      for (let referencePath in linkReferences) {
        for (let contractName in linkReferences[referencePath]) {
          referencesContractNames.push(contractName)
        }
      }
      if (referencesContractNames.length > 0) {
        result[contractName] = referencesContractNames
      }
    } catch (err) {
      console.log("Warning while parsing link libraries:", err)
    }
  }
  return result
}

export async function retrieveLinkReferences(artifactDirectory: string) {
  const filePaths = await retrieveFiles(artifactDirectory, "Test|test|dbg", "")
  const references = await parseLinkedLibraries(filePaths)
  return references
}

// retrieveLinkReferences("./artifacts/contracts").then(console.log)
