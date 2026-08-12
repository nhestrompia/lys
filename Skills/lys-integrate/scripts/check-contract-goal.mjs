#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const stop = new Set([
  "and", "app", "check", "flow", "for", "page", "screen", "test", "the", "this",
  "through", "to", "validate", "verify", "with",
]);

function tokens(value) {
  return new Set(String(value ?? "").toLowerCase().split(/[^a-z0-9]+/)
    .filter((token) => token.length > 2 && !stop.has(token)));
}

function searchable(item) {
  return tokens([item.id, item.title, item.description].filter(Boolean).join(" "));
}

function overlaps(goal, item) {
  const values = searchable(item);
  return [...goal].some((token) => values.has(token));
}

const rawArguments = process.argv.slice(2);
const rawPath = rawArguments.shift() ?? ".lys/contract.json";
const currentRouteIndex = rawArguments.indexOf("--current-route");
let currentRoute;
if (currentRouteIndex >= 0) {
  currentRoute = rawArguments[currentRouteIndex + 1];
  rawArguments.splice(currentRouteIndex, 2);
  if (!currentRoute) {
    console.error("--current-route requires a declared route ID");
    process.exit(64);
  }
}
const goalParts = rawArguments;
const goalText = goalParts.join(" ").trim();
if (!goalText) {
  console.error(
    "Usage: check-contract-goal.mjs <contract.json> <requested user goal> [--current-route <id>]",
  );
  process.exit(64);
}

const contract = JSON.parse(await readFile(resolve(rawPath), "utf8"));
if (contract.schemaVersion !== 2) {
  console.error(`Unsupported Lys contract schema ${contract.schemaVersion}; regenerate schema version 2 with the current SDK.`);
  process.exit(5);
}

const routeIDs = new Set((contract.routes ?? []).map((item) => item.id));
const appEntryRoutes = contract.app?.entryRoutes;
if (!Array.isArray(appEntryRoutes) || !appEntryRoutes.length) {
  console.error("Contract app.entryRoutes must declare the real screens where testing can begin.");
  process.exit(5);
}
for (const route of appEntryRoutes) {
  if (!routeIDs.has(route)) {
    console.error(`Contract app.entryRoutes references unknown route ${route}.`);
    process.exit(5);
  }
}
const safeEdges = (contract.capabilities ?? []).filter((item) =>
  item.route && item.resultsIn && item.risk !== "destructive" && item.risk !== "external");
function canReach(source, destination) {
  if (source === destination) return true;
  const queue = [source];
  const visited = new Set(queue);
  while (queue.length) {
    const route = queue.shift();
    for (const action of safeEdges.filter((item) => item.route === route)) {
      if (action.resultsIn === destination) return true;
      if (!visited.has(action.resultsIn)) {
        visited.add(action.resultsIn);
        queue.push(action.resultsIn);
      }
    }
  }
  return false;
}
const actionsByID = new Map((contract.capabilities ?? []).map((item) => [item.id, item]));
function failContract(message) {
  console.error(message);
  process.exit(5);
}
function routeAfter(steps, startRoute, owner) {
  let current = startRoute;
  for (const step of steps ?? []) {
    if (step.kind === "navigate") {
      if (!canReach(current, step.route)) {
        failContract(`${owner} step ${step.id} cannot navigate from ${current} to ${step.route}.`);
      }
      current = step.route;
    } else if (step.kind === "invoke") {
      const action = actionsByID.get(step.capability);
      if (!action) failContract(`${owner} step ${step.id} references unknown action ${step.capability}.`);
      if (action.route && action.route !== current) {
        failContract(`${owner} step ${step.id} invokes ${action.id} on ${current}, but it belongs to ${action.route}.`);
      }
      if (action.resultsIn) current = action.resultsIn;
      const expected = (step.expect ?? []).find((item) => item.kind === "route")?.route;
      if (expected) {
        if (action.resultsIn && current !== expected) {
          failContract(`${owner} step ${step.id} declares result ${current}, but expects ${expected}.`);
        }
        current = expected;
      }
    } else if (step.kind === "repeatUntil") {
      current = routeAfter(step.steps, current, `${owner} repeat ${step.id}`);
      if (step.until?.kind === "route") current = step.until.route;
    }
  }
  return current;
}
for (const flow of contract.flows ?? []) {
  if (!routeIDs.has(flow.startRoute) || !Array.isArray(flow.entryRoutes) || !flow.entryRoutes.length) {
    console.error(`Flow ${flow.id} is missing a valid startRoute or entryRoutes declaration.`);
    process.exit(5);
  }
  for (const entry of flow.entryRoutes) {
    if (!routeIDs.has(entry) || !canReach(entry, flow.startRoute)) {
      console.error(
        `Flow ${flow.id} cannot reach ${flow.startRoute} from ${entry}. ` +
        `Declare the real navigation control with route and resultsIn.`,
      );
      process.exit(5);
    }
  }
  const context = (contract.contexts ?? []).find((item) => item.id === flow.context);
  const requiredEntries = context &&
    (context.mode === "authenticatedSession" || (context.prepare ?? []).length)
    ? (context.readyWhen ?? []).filter((item) => item.kind === "route").map((item) => item.route)
    : appEntryRoutes;
  if (!requiredEntries.length) {
    console.error(`Flow ${flow.id} context needs a route readyWhen so entry coverage can be proven.`);
    process.exit(5);
  }
  for (const entry of requiredEntries) {
    if (!flow.entryRoutes.includes(entry)) {
      console.error(
        `Flow ${flow.id} omits required entry route ${entry}. ` +
        `Declare the real navigation action with route/resultsIn and add the entry.`,
      );
      process.exit(5);
    }
  }
  const finalRoute = routeAfter(flow.steps, flow.startRoute, `Flow ${flow.id}`);
  for (const accepted of (flow.acceptance ?? []).filter((item) => item.kind === "route")) {
    if (accepted.route !== finalRoute) {
      failContract(`Flow ${flow.id} ends on ${finalRoute}, not acceptance route ${accepted.route}.`);
    }
  }
}
for (const context of contract.contexts ?? []) {
  if (!(context.prepare ?? []).length) continue;
  if (!routeIDs.has(context.startRoute) || !Array.isArray(context.entryRoutes) || !context.entryRoutes.length) {
    console.error(`Context ${context.id} preparation is missing a valid startRoute or entryRoutes declaration.`);
    process.exit(5);
  }
  for (const entry of context.entryRoutes) {
    if (!routeIDs.has(entry) || !canReach(entry, context.startRoute)) {
      console.error(`Context ${context.id} cannot reach ${context.startRoute} from ${entry}.`);
      process.exit(5);
    }
  }
  if (context.mode === "uiFlow") {
    for (const entry of appEntryRoutes) {
      if (!context.entryRoutes.includes(entry)) {
        console.error(`Context ${context.id} omits app entry route ${entry}.`);
        process.exit(5);
      }
    }
  }
  const finalRoute = routeAfter(context.prepare, context.startRoute, `Context ${context.id}`);
  for (const ready of (context.readyWhen ?? []).filter((item) => item.kind === "route")) {
    if (ready.route !== finalRoute) {
      failContract(`Context ${context.id} preparation ends on ${finalRoute}, not ${ready.route}.`);
    }
  }
}
const goal = tokens(goalText);
const flows = (contract.flows ?? []).filter((item) => overlaps(goal, item));
const routes = (contract.routes ?? []).filter((item) => overlaps(goal, item));
const capabilities = (contract.capabilities ?? []).filter((item) => overlaps(goal, item));

if (flows.length === 1) {
  const flow = flows[0];
  if (currentRoute) {
    if (!routeIDs.has(currentRoute)) {
      console.error(`Observed current route ${currentRoute} is not declared in the contract.`);
      process.exit(6);
    }
    if (!canReach(currentRoute, flow.startRoute)) {
      console.error(
        `Observed current route ${currentRoute} cannot safely reach ${flow.startRoute} for ${flow.id}.`,
      );
      process.exit(6);
    }
  }
  console.log(`Declared coverage: ${flow.id}`);
  if (currentRoute) {
    console.log(
      `Runtime recovery: ${currentRoute} -> ${flow.startRoute} through the safe declared graph.`,
    );
  }
  process.exit(0);
}
if (flows.length > 1) {
  console.error(`Ambiguous declared coverage: ${flows.map((item) => item.id).join(", ")}`);
  process.exit(2);
}
if (routes.length || capabilities.length) {
  console.error(
    `Only exploratory coverage exists for “${goalText}”. Add a bounded flow and acceptance criteria. ` +
    `Related semantics: ${[...routes, ...capabilities].map((item) => item.id).join(", ")}`,
  );
  process.exit(3);
}
console.error(`No Lys semantics cover “${goalText}”. Instrument its real screen and actions first.`);
process.exit(4);
