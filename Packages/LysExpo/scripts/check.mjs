import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = await readFile(resolve(root, "src/index.ts"), "utf8");
const podspec = await readFile(resolve(root, "ios/LysTestKit.podspec"), "utf8");
const moduleConfig = JSON.parse(await readFile(resolve(root, "expo-module.config.json"), "utf8"));
const manifest = JSON.parse(await readFile(resolve(root, "package.json"), "utf8"));

const required = [
  "authenticatedContext", "signedOutContext", "defineContract", "validateContract",
  "serializeContract", "application", "flow", "navigate", "invoke", "uiContext",
  "actionProps", "screenProps", "stateProps",
];
for (const symbol of required) {
  if (!source.includes(`function ${symbol}`) && !source.includes(`const ${symbol}`)) {
    throw new Error(`Missing SDK symbol: ${symbol}`);
  }
}
if (manifest.name !== "@nhestrompia/lys") throw new Error("Unexpected package name");
if (manifest.main !== "dist/index.js") throw new Error("Package must load compiled JavaScript");
if (manifest.types !== "dist/index.d.ts") throw new Error("Package types must load built declarations");
if (manifest.publishConfig?.access !== "public") throw new Error("Scoped package must publish publicly");
await readFile(resolve(root, manifest.main), "utf8");
await readFile(resolve(root, manifest.types), "utf8");
if (!moduleConfig.apple.modules.includes("LysModule")) throw new Error("Native module is not linked");
if (!podspec.includes("s.dependency 'ExpoModulesCore'")) {
  throw new Error("Native module podspec must depend on ExpoModulesCore");
}
console.log("Lys Expo SDK contract check passed");
