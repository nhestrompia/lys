import { readFile } from "node:fs/promises";

const tag = process.argv[2] ?? process.env.GITHUB_REF_NAME;
if (!tag) {
  throw new Error("Pass a release tag, for example: npm run release:check -- v0.4.0");
}

const match = /^v(\d+\.\d+\.\d+)$/.exec(tag);
if (!match) {
  throw new Error(`Release tag must use stable semver vX.Y.Z; received ${tag}`);
}

const version = match[1];
const manifest = JSON.parse(
  await readFile(new URL("../Packages/LysExpo/package.json", import.meta.url)),
);
const lock = JSON.parse(await readFile(new URL("../package-lock.json", import.meta.url)));
const locked = lock.packages?.["Packages/LysExpo"]?.version;

if (manifest.version !== version) {
  throw new Error(
    `Tag ${tag} does not match Packages/LysExpo/package.json (${manifest.version})`,
  );
}
if (locked !== version) {
  throw new Error(`package-lock.json has ${locked ?? "no SDK version"}; expected ${version}`);
}
if (manifest.repository?.url !== "https://github.com/nhestrompia/lys.git") {
  throw new Error("The npm repository URL must match the GitHub trusted publisher repository");
}

console.log(`Release metadata is consistent for ${tag}`);
