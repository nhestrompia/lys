import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(import.meta.url);
const lys = require(resolve(root, "dist/index.js"));
const lysNode = require(resolve(root, "dist/node.js"));

const home = lys.screen("home", "Home");
const done = lys.screen("done", "Done", true);
const finish = lys.action("finish", "Finish", { route: home, resultsIn: done });
const contract = lys.defineContract({
  app: lys.application({
    bundleIdentifier: "com.example.app", displayName: "Example", entryRoutes: [home],
  }),
  routes: [home, done],
  capabilities: [finish],
  contexts: [lys.authenticatedContext({
    id: "authenticated.user",
    title: "Authenticated user",
    tokenEnvironmentKey: "LYS_TEST_SESSION_TOKEN",
    tokenSecret: "test.session",
    readyWhen: [lys.route(home)],
  })],
  flows: [lys.flow({
    id: "flow.finish",
    title: "Finish",
    context: "authenticated.user",
    startRoute: home,
    entryRoutes: [home],
    steps: [lys.invoke("finish", "Finish", finish)],
    acceptance: [lys.route(done), { kind: "noCrash" }],
  })],
});

assert.match(lys.serializeContract(contract), /"flow.finish"/);
assert.deepEqual(lys.screenProps(home), {
  testID: "lys.screen.home", accessible: false, collapsable: false,
});
assert.equal(lys.screenProps(contract.routes[0]).testID, "lys.screen.home");
assert.equal(lys.actionProps(contract.capabilities[0]).testID, "lys.action.finish");
assert.throws(
  () => lys.actionProps("copied.id"),
  /shared declared screen\/action object/,
);
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
assert.throws(
  () => lys.validateContract({
    ...contract,
    routes: [...contract.routes, lys.screen("other", "Other")],
    flows: [{ ...contract.flows[0], entryRoutes: ["other"] }],
  }),
  /cannot reach start screen/,
);
assert.throws(
  () => lys.validateContract({
    ...contract,
    flows: [{
      ...contract.flows[0],
      context: undefined,
      startRoute: done.id,
      entryRoutes: [done.id, home.id],
      acceptance: [lys.route(done)],
    }],
  }),
  /action belongs to home/,
);
const onboarding = lys.screen("onboarding", "Onboarding");
const finishOnboarding = lys.action("onboarding.finish", "Finish onboarding", {
  route: onboarding, resultsIn: home,
});
const recovered = lys.validateContract({
  ...contract,
  app: lys.application({ entryRoutes: [onboarding] }),
  routes: [onboarding, ...contract.routes],
  capabilities: [finishOnboarding, ...contract.capabilities],
  flows: [{ ...contract.flows[0], context: undefined, entryRoutes: [onboarding.id] }],
});
assert.deepEqual(recovered.flows[0].entryRoutes, [onboarding.id, home.id]);

const exportRoot = await mkdtemp(resolve(tmpdir(), "lys-expo-sdk-"));
const exportPath = resolve(exportRoot, ".lys/contract.json");
await lysNode.writeContract(contract, exportPath);
assert.equal(JSON.parse(await readFile(exportPath, "utf8")).flows[0].id, "flow.finish");
await rm(exportRoot, { recursive: true, force: true });

console.log("Lys Expo SDK behavior tests passed");
