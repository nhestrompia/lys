import assert from "node:assert/strict";
import { createRequire } from "node:module";
import Module from "node:module";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";

const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === "expo-modules-core") {
    return { requireNativeModule: () => ({ isTestSession: () => false, credential: () => null }) };
  }
  return originalLoad.call(this, request, parent, isMain);
};

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(import.meta.url);
const lys = require(resolve(root, "dist/index.js"));
const lysNode = require(resolve(root, "dist/node.js"));

const contract = lys.defineContract({
  routes: [lys.screen("home", "Home"), lys.screen("done", "Done", true)],
  capabilities: [lys.action("finish", "Finish", { route: "home", resultsIn: "done" })],
  contexts: [lys.authenticatedContext({
    id: "authenticated.user",
    title: "Authenticated user",
    tokenEnvironmentKey: "LYS_TEST_SESSION_TOKEN",
    tokenSecret: "test.session",
    readyWhen: [lys.route("home")],
  })],
  flows: [{
    id: "flow.finish",
    title: "Finish",
    context: "authenticated.user",
    startRoute: "home",
    steps: [{ id: "finish", title: "Finish", kind: "invoke", capability: "finish" }],
    acceptance: [lys.route("done"), { kind: "noCrash" }],
  }],
});

assert.match(lys.serializeContract(contract), /"flow.finish"/);
assert.deepEqual(lys.screenProps("home"), {
  testID: "lys.screen.home", accessible: false, collapsable: false,
});
assert.throws(
  () => lys.validateContract({ ...contract, flows: [{ ...contract.flows[0], acceptance: [] }] }),
  /requires title, steps, and acceptance/,
);
assert.throws(
  () => lys.validateContract({ ...contract, capabilities: [
    { ...contract.capabilities[0], resultsIn: "missing" },
  ] }),
  /unknown result screen/,
);

const exportRoot = await mkdtemp(resolve(tmpdir(), "lys-expo-sdk-"));
const exportPath = resolve(exportRoot, ".lys/contract.json");
await lysNode.writeContract(contract, exportPath);
assert.equal(JSON.parse(await readFile(exportPath, "utf8")).flows[0].id, "flow.finish");
await rm(exportRoot, { recursive: true, force: true });

Module._load = originalLoad;
console.log("Lys Expo SDK behavior tests passed");
