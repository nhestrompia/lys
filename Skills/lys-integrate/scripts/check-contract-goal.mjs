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

const [, , rawPath = ".lys/contract.json", ...goalParts] = process.argv;
const goalText = goalParts.join(" ").trim();
if (!goalText) {
  console.error("Usage: check-contract-goal.mjs <contract.json> <requested user goal>");
  process.exit(64);
}

const contract = JSON.parse(await readFile(resolve(rawPath), "utf8"));
const goal = tokens(goalText);
const flows = (contract.flows ?? []).filter((item) => overlaps(goal, item));
const routes = (contract.routes ?? []).filter((item) => overlaps(goal, item));
const capabilities = (contract.capabilities ?? []).filter((item) => overlaps(goal, item));

if (flows.length === 1) {
  console.log(`Declared coverage: ${flows[0].id}`);
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
