"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.writeContract = writeContract;
const promises_1 = require("node:fs/promises");
const node_path_1 = require("node:path");
const index_1 = require("./index");
/** Writes a validated contract from a Node-based export script or test setup. */
async function writeContract(contract, path = ".lys/contract.json") {
    await (0, promises_1.mkdir)((0, node_path_1.dirname)(path), { recursive: true });
    await (0, promises_1.writeFile)(path, (0, index_1.serializeContract)(contract), "utf8");
}
//# sourceMappingURL=node.js.map