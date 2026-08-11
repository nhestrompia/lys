"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.testSession = exports.stateEquals = exports.visible = exports.route = exports.LysContractValidationError = void 0;
exports.validateContract = validateContract;
exports.serializeContract = serializeContract;
exports.screen = screen;
exports.action = action;
exports.screenProps = screenProps;
exports.actionProps = actionProps;
exports.stateProps = stateProps;
exports.authenticatedContext = authenticatedContext;
exports.signedOutContext = signedOutContext;
exports.defineContract = defineContract;
class LysContractValidationError extends Error {
    constructor(message) {
        super(message);
        this.name = "LysContractValidationError";
    }
}
exports.LysContractValidationError = LysContractValidationError;
const identifierPattern = /^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$/;
const environmentPattern = /^[A-Za-z_][A-Za-z0-9_]*$/;
function fail(message) {
    throw new LysContractValidationError(message);
}
function unique(ids, kind) {
    if (!ids.every((id) => identifierPattern.test(id) && id.length <= 128)) {
        fail(`Every ${kind} ID must be stable and dot-separated`);
    }
    if (new Set(ids).size !== ids.length)
        fail(`Duplicate ${kind} IDs are not allowed`);
}
function validateSelector(selector, owner) {
    if (!selector || ![selector.identifier, selector.name, selector.text].some(Boolean)) {
        fail(`${owner} selector requires identifier, name, or text`);
    }
    if (selector.index != null && selector.index < 0)
        fail(`${owner} selector index cannot be negative`);
}
function validatePredicate(predicate, owner, screens) {
    switch (predicate.kind) {
        case "route":
            if (!predicate.route || !screens.has(predicate.route))
                fail(`${owner} references an unknown route`);
            break;
        case "visible":
        case "absent":
        case "enabled":
        case "selected":
            validateSelector(predicate.selector, owner);
            break;
        case "value":
            validateSelector(predicate.selector, owner);
            if (predicate.equals == null)
                fail(`${owner} value predicate requires equals`);
            break;
        case "text":
            validateSelector(predicate.selector, owner);
            if (!predicate.matches)
                fail(`${owner} text predicate requires matches`);
            break;
    }
}
function validateParameter(parameter, owner) {
    if (!["string", "number", "boolean", "enum"].includes(parameter.type)) {
        fail(`${owner} has unsupported type ${parameter.type}`);
    }
    if (parameter.type === "enum" && !parameter.values?.length)
        fail(`${owner} enum requires values`);
}
function validateInput(input, owner) {
    const entries = Object.entries(input);
    if (entries.length !== 1)
        fail(`${owner} must have exactly one source`);
    const [kind, value] = entries[0] ?? [];
    if (!["literal", "parameter", "secret"].includes(kind) || typeof value !== "string") {
        fail(`${owner} has an invalid source`);
    }
    if (kind !== "literal" && !identifierPattern.test(value))
        fail(`${owner} has an invalid ID`);
}
function validateSteps(steps, owner, screens, actions) {
    unique(steps.map((step) => step.id), `step in ${owner}`);
    for (const step of steps) {
        if (!step.title.trim())
            fail(`${owner} step ${step.id} requires a title`);
        Object.entries(step.arguments ?? {}).forEach(([name, input]) => validateInput(input, `${owner} step ${step.id} argument ${name}`));
        if (step.kind === "navigate" && (!step.route || !screens.has(step.route))) {
            fail(`${owner} step ${step.id} references an unknown screen`);
        }
        if (step.kind === "invoke" && (!step.capability || !actions.has(step.capability))) {
            fail(`${owner} step ${step.id} references an unknown action`);
        }
        if (step.kind === "assert" && !step.predicate)
            fail(`${owner} step ${step.id} requires a predicate`);
        if (step.kind === "repeatUntil") {
            if (!step.until || !step.steps?.length || !step.maximumIterations ||
                step.maximumIterations < 1 || step.maximumIterations > 1000) {
                fail(`${owner} repeat step ${step.id} requires until, steps, and a 1...1000 limit`);
            }
            validateSteps(step.steps, `${owner} repeat ${step.id}`, screens, actions);
        }
        if (step.predicate)
            validatePredicate(step.predicate, `${owner} step ${step.id}`, screens);
        if (step.until)
            validatePredicate(step.until, `${owner} step ${step.id}`, screens);
        step.expect?.forEach((item) => validatePredicate(item, `${owner} step ${step.id}`, screens));
    }
}
function stepSecrets(steps) {
    const result = new Set();
    for (const step of steps) {
        Object.values(step.arguments ?? {}).forEach((input) => {
            if ("secret" in input)
                result.add(input.secret);
        });
        stepSecrets(step.steps ?? []).forEach((secret) => result.add(secret));
    }
    return result;
}
/** Validates the same cross-references and bounded-flow rules enforced by the Lys runner. */
function validateContract(contract) {
    if (contract.schemaVersion !== 1)
        fail(`Unsupported schemaVersion ${contract.schemaVersion}`);
    if (!contract.flows.length)
        fail("A contract requires at least one flow");
    unique(contract.routes.map((item) => item.id), "screen");
    unique(contract.capabilities.map((item) => item.id), "action");
    unique(contract.contexts.map((item) => item.id), "context");
    unique(contract.flows.map((item) => item.id), "flow");
    const screens = new Set(contract.routes.map((item) => item.id));
    const actions = new Set(contract.capabilities.map((item) => item.id));
    const contexts = new Set(contract.contexts.map((item) => item.id));
    for (const screen of contract.routes) {
        if (!screen.title.trim() || !screen.match.length)
            fail(`Screen ${screen.id} requires title and match predicates`);
        if (screen.match.some((item) => item.kind === "route"))
            fail(`Screen ${screen.id} cannot recursively match a route`);
        screen.match.forEach((item) => validatePredicate(item, `Screen ${screen.id}`, screens));
    }
    for (const item of contract.capabilities) {
        if (!item.title.trim())
            fail(`Action ${item.id} requires a title`);
        validateSelector(item.selector, `Action ${item.id}`);
        if (item.route && !screens.has(item.route))
            fail(`Action ${item.id} references unknown screen ${item.route}`);
        if (item.resultsIn && !screens.has(item.resultsIn))
            fail(`Action ${item.id} references unknown result screen ${item.resultsIn}`);
        Object.entries(item.parameters ?? {}).forEach(([name, parameter]) => validateParameter(parameter, `Action ${item.id} parameter ${name}`));
    }
    for (const context of contract.contexts) {
        if (!context.title.trim() || !context.readyWhen.length)
            fail(`Context ${context.id} requires title and readyWhen`);
        if (context.mode === "uiFlow" && context.session)
            fail(`UI context ${context.id} cannot declare a session fixture`);
        if (context.mode === "authenticatedSession") {
            if (!context.session || !Object.keys(context.session.environment).length) {
                fail(`Authenticated context ${context.id} requires a session environment`);
            }
            const secrets = new Set(context.requiredSecrets ?? []);
            for (const [key, input] of Object.entries(context.session.environment)) {
                if (!environmentPattern.test(key))
                    fail(`Authenticated context ${context.id} has invalid environment key ${key}`);
                validateInput(input, `Authenticated context ${context.id} environment ${key}`);
                if ("secret" in input && !secrets.has(input.secret)) {
                    fail(`Authenticated context ${context.id} must declare secret ${input.secret}`);
                }
            }
        }
        unique(context.requiredSecrets ?? [], "secret");
        validateSteps(context.prepare, `Context ${context.id}`, screens, actions);
        for (const secret of stepSecrets(context.prepare)) {
            if (!context.requiredSecrets?.includes(secret))
                fail(`Context ${context.id} must declare step secret ${secret}`);
        }
        context.readyWhen.forEach((item) => validatePredicate(item, `Context ${context.id}`, screens));
    }
    for (const flow of contract.flows) {
        if (!flow.title.trim() || !flow.steps.length || !flow.acceptance.length) {
            fail(`Flow ${flow.id} requires title, steps, and acceptance predicates`);
        }
        if (flow.context && !contexts.has(flow.context))
            fail(`Flow ${flow.id} references unknown context ${flow.context}`);
        if (flow.startRoute && !screens.has(flow.startRoute))
            fail(`Flow ${flow.id} references unknown start screen ${flow.startRoute}`);
        unique(flow.requiredSecrets ?? [], "secret");
        for (const [name, parameter] of Object.entries(flow.parameters ?? {})) {
            validateParameter(parameter, `Flow ${flow.id} parameter ${name}`);
        }
        for (const secret of stepSecrets(flow.steps)) {
            if (!flow.requiredSecrets?.includes(secret))
                fail(`Flow ${flow.id} must declare step secret ${secret}`);
        }
        validateSteps(flow.steps, `Flow ${flow.id}`, screens, actions);
        flow.acceptance.forEach((item) => validatePredicate(item, `Flow ${flow.id}`, screens));
    }
    return contract;
}
function serializeContract(contract) {
    return `${JSON.stringify(validateContract(contract), null, 2)}\n`;
}
const route = (id) => ({ kind: "route", route: id });
exports.route = route;
const visible = (identifier) => ({
    kind: "visible",
    selector: { identifier },
});
exports.visible = visible;
const stateEquals = (id, value) => ({
    kind: "value",
    selector: { identifier: `lys.state.${id}` },
    equals: value,
});
exports.stateEquals = stateEquals;
function screen(id, title, terminal = false) {
    return {
        id,
        title,
        match: [(0, exports.visible)(`lys.screen.${id}`)],
        ...(terminal ? { terminal: true } : {}),
    };
}
function action(id, title, options = {}) {
    return {
        id,
        title,
        action: options.action ?? "tap",
        selector: options.selector ?? { identifier: `lys.action.${id}` },
        ...options,
    };
}
function screenProps(id) {
    // A React Native container with accessible=true collapses its descendants into one element,
    // hiding nested buttons from XCTest. Keep the native view and expose its testID without grouping.
    return { testID: `lys.screen.${id}`, accessible: false, collapsable: false };
}
function actionProps(id) {
    return { testID: `lys.action.${id}`, accessible: true };
}
function stateProps(id, value) {
    return {
        testID: `lys.state.${id}`,
        accessible: true,
        accessibilityValue: { text: String(value) },
    };
}
function authenticatedContext(options) {
    return {
        id: options.id,
        title: options.title,
        mode: "authenticatedSession",
        requiredSecrets: [options.tokenSecret],
        prepare: [],
        readyWhen: options.readyWhen,
        session: {
            environment: {
                [options.tokenEnvironmentKey]: { secret: options.tokenSecret },
            },
            arguments: ["-LysTesting"],
        },
    };
}
function signedOutContext(readyWhen, id = "signedOut") {
    return { id, title: "Signed-out user", mode: "uiFlow", prepare: [], readyWhen };
}
function defineContract(contract) {
    return validateContract({ schemaVersion: 1, ...contract });
}
let nativeModule;
function native() {
    // Keep the contract/export surface Node-safe. Metro still sees the static module name, while
    // Node contract scripts never load ExpoModulesCore unless they explicitly call testSession.
    nativeModule ?? (nativeModule = require("expo-modules-core").requireNativeModule("Lys"));
    return nativeModule;
}
exports.testSession = {
    isEnabled: () => native().isTestSession(),
    credential: (environmentKey) => native().credential(environmentKey),
};
//# sourceMappingURL=index.js.map