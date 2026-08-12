import { mkdir, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { LysContract, serializeContract } from "./index";

/** Writes a validated contract from a Node-based export script or test setup. */
export async function writeContract(
  contract: LysContract,
  path = ".lys/contract.json",
): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, serializeContract(contract), "utf8");
}
