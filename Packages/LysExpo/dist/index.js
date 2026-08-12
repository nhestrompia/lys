"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.testSession = exports.stateEquals = exports.visible = exports.route = exports.LysContractValidationError = void 0;
exports.expandRecoverableEntries = expandRecoverableEntries;
exports.validateContract = validateContract;
exports.serializeContract = serializeContract;
exports.screen = screen;
exports.action = action;
exports.flow = flow;
exports.navigate = navigate;
exports.invoke = invoke;
exports.uiContext = uiContext;
exports.application = application;
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
function hasNavigationPath(source, destination, capabilities) {
    if (source === destination)
        return true;
    const edges = capabilities.filter((item) => item.route && item.resultsIn && item.risk !== "destructive" && item.risk !== "external");
    const queue = [source];
    const visited = new Set([source]);
    while (queue.length) {
        const route = queue.shift();
        for (const action of edges.filter((item) => item.route === route)) {
            const next = action.resultsIn;
            if (visited.has(next))
                continue;
            if (next === destination)
                return true;
            visited.add(next);
            queue.push(next);
        }
    }
    return false;
}
/**
 * Expands developer-declared coverage roots with every known route that can safely reach each
 * flow's start. This keeps a restored/running app usable without requiring developers to predict
 * every screen on which a user might leave it.
 */
function expandRecoverableEntries(contract) {
    return {
        ...contract,
        flows: contract.flows.map((item) => {
            const seen = new Set();
            const recoverable = contract.routes
                .map((route) => route.id)
                .filter((route) => hasNavigationPath(route, item.startRoute, contract.capabilities));
            return {
                ...item,
                entryRoutes: [...item.entryRoutes, ...recoverable]
                    .filter((route) => !seen.has(route) && Boolean(seen.add(route))),
            };
        }),
    };
}
function validateRouteExecution(steps, startRoute, owner, capabilities) {
    let current = startRoute;
    const byID = new Map(capabilities.map((item) => [item.id, item]));
    for (const step of steps) {
        if (step.kind === "navigate") {
            if (!step.route || !hasNavigationPath(current, step.route, capabilities)) {
                fail(`${owner} step ${step.id} cannot navigate from ${current} to ${step.route ?? "unknown"}`);
            }
            current = step.route;
        }
        else if (step.kind === "invoke") {
            const action = step.capability ? byID.get(step.capability) : undefined;
            if (!action)
                continue;
            if (action.route && action.route !== current) {
                fail(`${owner} step ${step.id} invokes ${action.id} on ${current}, but the action belongs to ${action.route}`);
            }
            if (action.resultsIn)
                current = action.resultsIn;
            const expected = step.expect?.find((item) => item.kind === "route")?.route;
            if (expected) {
                if (action.resultsIn && current !== expected) {
                    fail(`${owner} step ${step.id} declares result ${current}, but expects route ${expected}`);
                }
                current = expected;
            }
        }
        else if (step.kind === "repeatUntil") {
            current = validateRouteExecution(step.steps ?? [], current, `${owner} repeat ${step.id}`, capabilities);
            if (step.until?.kind === "route" && step.until.route)
                current = step.until.route;
        }
    }
    return current;
}
/** Validates the same cross-references and bounded-flow rules enforced by the Lys runner. */
function validateContract(contract) {
    contract = expandRecoverableEntries(contract);
    if (contract.schemaVersion !== 2)
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
    if (!contract.app?.entryRoutes?.length) {
        fail("Contract app.entryRoutes must declare the real screens where testing can begin");
    }
    unique(contract.app.entryRoutes, "app entry screen");
    for (const entryRoute of contract.app.entryRoutes) {
        if (!screens.has(entryRoute))
            fail(`App entryRoutes references unknown screen ${entryRoute}`);
    }
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
        if (context.prepare.length) {
            if (!context.startRoute || !screens.has(context.startRoute)) {
                fail(`Context ${context.id} preparation requires a valid startRoute`);
            }
            if (!context.entryRoutes?.length)
                fail(`Context ${context.id} preparation requires entryRoutes`);
            unique(context.entryRoutes, `entry route in context ${context.id}`);
            for (const entryRoute of context.entryRoutes) {
                if (!screens.has(entryRoute))
                    fail(`Context ${context.id} references unknown entry route ${entryRoute}`);
                if (!hasNavigationPath(entryRoute, context.startRoute, contract.capabilities)) {
                    fail(`Context ${context.id} cannot reach start screen ${context.startRoute} from entry route ${entryRoute}`);
                }
            }
            if (context.mode === "uiFlow") {
                for (const appEntry of contract.app.entryRoutes) {
                    if (!context.entryRoutes.includes(appEntry)) {
                        fail(`Context ${context.id} must support app entry screen ${appEntry}; declare its recovery path before preparation`);
                    }
                }
            }
            const finalRoute = validateRouteExecution(context.prepare, context.startRoute, `Context ${context.id}`, contract.capabilities);
            for (const readyRoute of context.readyWhen.filter((item) => item.kind === "route")) {
                if (readyRoute.route !== finalRoute) {
                    fail(`Context ${context.id} preparation ends on ${finalRoute}, not ready route ${readyRoute.route}`);
                }
            }
        }
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
        if (!screens.has(flow.startRoute))
            fail(`Flow ${flow.id} references unknown start screen ${flow.startRoute}`);
        if (!flow.entryRoutes?.length)
            fail(`Flow ${flow.id} requires at least one supported entry route`);
        unique(flow.entryRoutes, `entry route in flow ${flow.id}`);
        for (const entryRoute of flow.entryRoutes) {
            if (!screens.has(entryRoute))
                fail(`Flow ${flow.id} references unknown entry route ${entryRoute}`);
            if (!hasNavigationPath(entryRoute, flow.startRoute, contract.capabilities)) {
                fail(`Flow ${flow.id} cannot reach start screen ${flow.startRoute} from entry route ${entryRoute}; declare the missing action resultsIn transition`);
            }
        }
        if (flow.context) {
            const context = contract.contexts.find((item) => item.id === flow.context);
            const readyRoutes = context.readyWhen.filter((item) => item.kind === "route").map((item) => item.route);
            for (const route of readyRoutes) {
                if (!flow.entryRoutes.includes(route)) {
                    fail(`Flow ${flow.id} context becomes ready on ${route}, but that route is missing from entryRoutes`);
                }
            }
        }
        const context = flow.context
            ? contract.contexts.find((item) => item.id === flow.context)
            : undefined;
        const requiredEntries = context &&
            (context.mode === "authenticatedSession" || context.prepare.length)
            ? context.readyWhen.filter((item) => item.kind === "route").map((item) => item.route)
            : contract.app.entryRoutes;
        if (!requiredEntries.length) {
            fail(`Flow ${flow.id} context must declare a route readyWhen so entry coverage can be proven`);
        }
        for (const entryRoute of requiredEntries) {
            if (!flow.entryRoutes.includes(entryRoute)) {
                fail(`Flow ${flow.id} does not support required entry screen ${entryRoute}; add the real navigation action with route/resultsIn, then include it in entryRoutes`);
            }
        }
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
        const finalRoute = validateRouteExecution(flow.steps, flow.startRoute, `Flow ${flow.id}`, contract.capabilities);
        for (const accepted of flow.acceptance.filter((item) => item.kind === "route")) {
            if (accepted.route !== finalRoute) {
                fail(`Flow ${flow.id} ends on ${finalRoute}, not acceptance route ${accepted.route}`);
            }
        }
    }
    return contract;
}
function serializeContract(contract) {
    return `${JSON.stringify(validateContract(contract), null, 2)}\n`;
}
const route = (reference) => ({
    kind: "route", route: semanticID(reference),
});
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
    const { route: source, resultsIn, ...rest } = options;
    return {
        id,
        title,
        action: options.action ?? "tap",
        selector: options.selector ?? { identifier: `lys.action.${id}` },
        ...rest,
        ...(source ? { route: semanticID(source) } : {}),
        ...(resultsIn ? { resultsIn: semanticID(resultsIn) } : {}),
    };
}
function flow(options) {
    return {
        ...options,
        startRoute: semanticID(options.startRoute),
        entryRoutes: options.entryRoutes.map(semanticID),
    };
}
function navigate(id, title, destination) {
    return { id, title, kind: "navigate", route: semanticID(destination) };
}
function invoke(id, title, capability, options = {}) {
    return { ...options, id, title, kind: "invoke", capability: semanticID(capability) };
}
function uiContext(options) {
    return {
        ...options,
        mode: "uiFlow",
        startRoute: semanticID(options.startRoute),
        entryRoutes: options.entryRoutes.map(semanticID),
    };
}
function semanticID(reference) {
    if (!reference || typeof reference !== "object" || !reference.id) {
        fail("Lys semantic helpers require a shared declared screen/action object, not a copied string ID");
    }
    return reference.id;
}
function application(options) {
    return { ...options, entryRoutes: options.entryRoutes.map(semanticID) };
}
function screenProps(reference) {
    const id = semanticID(reference);
    // A React Native container with accessible=true collapses its descendants into one element,
    // hiding nested buttons from XCTest. Keep the native view and expose its testID without grouping.
    return { testID: `lys.screen.${id}`, accessible: false, collapsable: false };
}
function actionProps(reference) {
    const id = semanticID(reference);
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
    return validateContract({ schemaVersion: 2, ...contract });
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