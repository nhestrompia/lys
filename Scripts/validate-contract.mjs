import Ajv2020 from "ajv/dist/2020.js";
import { readFile } from "node:fs/promises";

const schema = JSON.parse(await readFile(new URL("../Schemas/lys-test-contract.schema.json", import.meta.url)));
const example = JSON.parse(await readFile(new URL("../Examples/lys-contract.json", import.meta.url)));
const ajv = new Ajv2020({ allErrors: true, strict: true, strictRequired: false });
const validate = ajv.compile(schema);

if (!validate(example)) {
  throw new Error(`Example contract does not satisfy the canonical schema: ${ajv.errorsText(validate.errors)}`);
}

const broken = structuredClone(example);
broken.flows[0].acceptance = [];
if (validate(broken)) throw new Error("Schema accepted a flow with no acceptance criteria");

const missingEntry = structuredClone(example);
delete missingEntry.flows[0].entryRoutes;
if (validate(missingEntry)) throw new Error("Schema accepted a flow with no entry routes");

const missingAppEntry = structuredClone(example);
delete missingAppEntry.app.entryRoutes;
if (validate(missingAppEntry)) throw new Error("Schema accepted an app with no testing entry routes");

const missingContextEntry = structuredClone(example);
delete missingContextEntry.contexts.find((item) => item.id === "signedOut").startRoute;
if (validate(missingContextEntry)) {
  throw new Error("Schema accepted UI preparation with no start route");
}

console.log("Lys JSON Schema conformance tests passed");
