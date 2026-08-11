import { requireNativeModule } from "expo-modules-core";

export type LysRisk = "readOnly" | "reversible" | "destructive" | "external";
export type LysActionKind =
  | "tap" | "doubleTap" | "longPress" | "type" | "clear" | "toggle" | "select"
  | "scrollUp" | "scrollDown" | "swipe" | "drag" | "setSlider" | "dismiss" | "back";

export type LysSelector = {
  identifier?: string;
  role?: string;
  name?: string;
  text?: string;
  above?: string;
  below?: string;
  descendantOf?: string;
  index?: number;
};

export type LysPredicate = {
  kind:
    | "route" | "visible" | "absent" | "enabled" | "selected" | "value" | "text"
    | "progressComplete" | "appIdle" | "noCrash";
  route?: string;
  selector?: LysSelector;
  equals?: string;
  matches?: string;
};

export type LysInput =
  | { literal: string }
  | { parameter: string }
  | { secret: string };

export type LysScreen = {
  id: string;
  title: string;
  match: LysPredicate[];
  terminal?: boolean;
};

export type LysAction = {
  id: string;
  title: string;
  route?: string;
  resultsIn?: string;
  action: LysActionKind;
  selector: LysSelector;
  risk?: LysRisk;
  parameters?: Record<string, {
    type: "string" | "number" | "boolean" | "enum";
    required?: boolean;
    values?: string[];
    sensitive?: boolean;
  }>;
};

export type LysStep = {
  id: string;
  title: string;
  kind: "navigate" | "invoke" | "assert" | "repeatUntil";
  route?: string;
  capability?: string;
  arguments?: Record<string, LysInput>;
  predicate?: LysPredicate;
  expect?: LysPredicate[];
  until?: LysPredicate;
  maximumIterations?: number;
  steps?: LysStep[];
};

export type LysContext = {
  id: string;
  title: string;
  mode: "uiFlow" | "authenticatedSession";
  requiredSecrets?: string[];
  prepare: LysStep[];
  readyWhen: LysPredicate[];
  session?: {
    environment: Record<string, LysInput>;
    arguments?: string[];
  };
};

export type LysFlow = {
  id: string;
  title: string;
  description?: string;
  context?: string;
  startRoute?: string;
  parameters?: LysAction["parameters"];
  requiredSecrets?: string[];
  steps: LysStep[];
  acceptance: LysPredicate[];
};

export type LysContract = {
  $schema?: string;
  schemaVersion: 1;
  app?: { bundleIdentifier?: string; displayName?: string };
  routes: LysScreen[];
  capabilities: LysAction[];
  contexts: LysContext[];
  flows: LysFlow[];
};

export class LysContractValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LysContractValidationError";
  }
}

const identifierPattern = /^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$/;
const environmentPattern = /^[A-Za-z_][A-Za-z0-9_]*$/;

function fail(message: string): never {
  throw new LysContractValidationError(message);
}

function unique(ids: string[], kind: string) {
  if (!ids.every((id) => identifierPattern.test(id) && id.length <= 128)) {
    fail(`Every ${kind} ID must be stable and dot-separated`);
  }
  if (new Set(ids).size !== ids.length) fail(`Duplicate ${kind} IDs are not allowed`);
}

function validateSelector(selector: LysSelector | undefined, owner: string) {
  if (!selector || ![selector.identifier, selector.name, selector.text].some(Boolean)) {
    fail(`${owner} selector requires identifier, name, or text`);
  }
  if (selector.index != null && selector.index < 0) fail(`${owner} selector index cannot be negative`);
}

function validatePredicate(predicate: LysPredicate, owner: string, screens: Set<string>) {
  switch (predicate.kind) {
    case "route":
      if (!predicate.route || !screens.has(predicate.route)) fail(`${owner} references an unknown route`);
      break;
    case "visible": case "absent": case "enabled": case "selected":
      validateSelector(predicate.selector, owner);
      break;
    case "value":
      validateSelector(predicate.selector, owner);
      if (predicate.equals == null) fail(`${owner} value predicate requires equals`);
      break;
    case "text":
      validateSelector(predicate.selector, owner);
      if (!predicate.matches) fail(`${owner} text predicate requires matches`);
      break;
  }
}

function validateParameter(
  parameter: NonNullable<LysAction["parameters"]>[string], owner: string,
) {
  if (!["string", "number", "boolean", "enum"].includes(parameter.type)) {
    fail(`${owner} has unsupported type ${parameter.type}`);
  }
  if (parameter.type === "enum" && !parameter.values?.length) fail(`${owner} enum requires values`);
}

function validateInput(input: LysInput, owner: string) {
  const entries = Object.entries(input);
  if (entries.length !== 1) fail(`${owner} must have exactly one source`);
  const [kind, value] = entries[0] ?? [];
  if (!["literal", "parameter", "secret"].includes(kind) || typeof value !== "string") {
    fail(`${owner} has an invalid source`);
  }
  if (kind !== "literal" && !identifierPattern.test(value)) fail(`${owner} has an invalid ID`);
}

function validateSteps(
  steps: LysStep[], owner: string, screens: Set<string>, actions: Set<string>,
) {
  unique(steps.map((step) => step.id), `step in ${owner}`);
  for (const step of steps) {
    if (!step.title.trim()) fail(`${owner} step ${step.id} requires a title`);
    Object.entries(step.arguments ?? {}).forEach(([name, input]) =>
      validateInput(input, `${owner} step ${step.id} argument ${name}`));
    if (step.kind === "navigate" && (!step.route || !screens.has(step.route))) {
      fail(`${owner} step ${step.id} references an unknown screen`);
    }
    if (step.kind === "invoke" && (!step.capability || !actions.has(step.capability))) {
      fail(`${owner} step ${step.id} references an unknown action`);
    }
    if (step.kind === "assert" && !step.predicate) fail(`${owner} step ${step.id} requires a predicate`);
    if (step.kind === "repeatUntil") {
      if (!step.until || !step.steps?.length || !step.maximumIterations ||
          step.maximumIterations < 1 || step.maximumIterations > 1000) {
        fail(`${owner} repeat step ${step.id} requires until, steps, and a 1...1000 limit`);
      }
      validateSteps(step.steps, `${owner} repeat ${step.id}`, screens, actions);
    }
    if (step.predicate) validatePredicate(step.predicate, `${owner} step ${step.id}`, screens);
    if (step.until) validatePredicate(step.until, `${owner} step ${step.id}`, screens);
    step.expect?.forEach((item) => validatePredicate(item, `${owner} step ${step.id}`, screens));
  }
}

function stepSecrets(steps: LysStep[]): Set<string> {
  const result = new Set<string>();
  for (const step of steps) {
    Object.values(step.arguments ?? {}).forEach((input) => {
      if ("secret" in input) result.add(input.secret);
    });
    stepSecrets(step.steps ?? []).forEach((secret) => result.add(secret));
  }
  return result;
}

/** Validates the same cross-references and bounded-flow rules enforced by the Lys runner. */
export function validateContract(contract: LysContract): LysContract {
  if (contract.schemaVersion !== 1) fail(`Unsupported schemaVersion ${contract.schemaVersion}`);
  if (!contract.flows.length) fail("A contract requires at least one flow");
  unique(contract.routes.map((item) => item.id), "screen");
  unique(contract.capabilities.map((item) => item.id), "action");
  unique(contract.contexts.map((item) => item.id), "context");
  unique(contract.flows.map((item) => item.id), "flow");
  const screens = new Set(contract.routes.map((item) => item.id));
  const actions = new Set(contract.capabilities.map((item) => item.id));
  const contexts = new Set(contract.contexts.map((item) => item.id));

  for (const screen of contract.routes) {
    if (!screen.title.trim() || !screen.match.length) fail(`Screen ${screen.id} requires title and match predicates`);
    if (screen.match.some((item) => item.kind === "route")) fail(`Screen ${screen.id} cannot recursively match a route`);
    screen.match.forEach((item) => validatePredicate(item, `Screen ${screen.id}`, screens));
  }
  for (const item of contract.capabilities) {
    if (!item.title.trim()) fail(`Action ${item.id} requires a title`);
    validateSelector(item.selector, `Action ${item.id}`);
    if (item.route && !screens.has(item.route)) fail(`Action ${item.id} references unknown screen ${item.route}`);
    if (item.resultsIn && !screens.has(item.resultsIn)) fail(`Action ${item.id} references unknown result screen ${item.resultsIn}`);
    Object.entries(item.parameters ?? {}).forEach(([name, parameter]) =>
      validateParameter(parameter, `Action ${item.id} parameter ${name}`));
  }
  for (const context of contract.contexts) {
    if (!context.title.trim() || !context.readyWhen.length) fail(`Context ${context.id} requires title and readyWhen`);
    if (context.mode === "uiFlow" && context.session) fail(`UI context ${context.id} cannot declare a session fixture`);
    if (context.mode === "authenticatedSession") {
      if (!context.session || !Object.keys(context.session.environment).length) {
        fail(`Authenticated context ${context.id} requires a session environment`);
      }
      const secrets = new Set(context.requiredSecrets ?? []);
      for (const [key, input] of Object.entries(context.session.environment)) {
        if (!environmentPattern.test(key)) fail(`Authenticated context ${context.id} has invalid environment key ${key}`);
        validateInput(input, `Authenticated context ${context.id} environment ${key}`);
        if ("secret" in input && !secrets.has(input.secret)) {
          fail(`Authenticated context ${context.id} must declare secret ${input.secret}`);
        }
      }
    }
    unique(context.requiredSecrets ?? [], "secret");
    validateSteps(context.prepare, `Context ${context.id}`, screens, actions);
    for (const secret of stepSecrets(context.prepare)) {
      if (!context.requiredSecrets?.includes(secret)) fail(`Context ${context.id} must declare step secret ${secret}`);
    }
    context.readyWhen.forEach((item) => validatePredicate(item, `Context ${context.id}`, screens));
  }
  for (const flow of contract.flows) {
    if (!flow.title.trim() || !flow.steps.length || !flow.acceptance.length) {
      fail(`Flow ${flow.id} requires title, steps, and acceptance predicates`);
    }
    if (flow.context && !contexts.has(flow.context)) fail(`Flow ${flow.id} references unknown context ${flow.context}`);
    if (flow.startRoute && !screens.has(flow.startRoute)) fail(`Flow ${flow.id} references unknown start screen ${flow.startRoute}`);
    unique(flow.requiredSecrets ?? [], "secret");
    for (const [name, parameter] of Object.entries(flow.parameters ?? {})) {
      validateParameter(parameter, `Flow ${flow.id} parameter ${name}`);
    }
    for (const secret of stepSecrets(flow.steps)) {
      if (!flow.requiredSecrets?.includes(secret)) fail(`Flow ${flow.id} must declare step secret ${secret}`);
    }
    validateSteps(flow.steps, `Flow ${flow.id}`, screens, actions);
    flow.acceptance.forEach((item) => validatePredicate(item, `Flow ${flow.id}`, screens));
  }
  return contract;
}

export function serializeContract(contract: LysContract): string {
  return `${JSON.stringify(validateContract(contract), null, 2)}\n`;
}

export const route = (id: string): LysPredicate => ({ kind: "route", route: id });
export const visible = (identifier: string): LysPredicate => ({
  kind: "visible",
  selector: { identifier },
});
export const stateEquals = (id: string, value: string): LysPredicate => ({
  kind: "value",
  selector: { identifier: `lys.state.${id}` },
  equals: value,
});

export function screen(id: string, title: string, terminal = false): LysScreen {
  return {
    id,
    title,
    match: [visible(`lys.screen.${id}`)],
    ...(terminal ? { terminal: true } : {}),
  };
}

export function action(
  id: string,
  title: string,
  options: Omit<LysAction, "id" | "title" | "action" | "selector"> & {
    action?: LysActionKind;
    selector?: LysSelector;
  } = {},
): LysAction {
  return {
    id,
    title,
    action: options.action ?? "tap",
    selector: options.selector ?? { identifier: `lys.action.${id}` },
    ...options,
  };
}

export function screenProps(id: string) {
  // A React Native container with accessible=true collapses its descendants into one element,
  // hiding nested buttons from XCTest. Keep the native view and expose its testID without grouping.
  return { testID: `lys.screen.${id}`, accessible: false, collapsable: false } as const;
}

export function actionProps(id: string) {
  return { testID: `lys.action.${id}`, accessible: true } as const;
}

export function stateProps(id: string, value: string | number | boolean) {
  return {
    testID: `lys.state.${id}`,
    accessible: true,
    accessibilityValue: { text: String(value) },
  } as const;
}

export function authenticatedContext(options: {
  id: string;
  title: string;
  tokenEnvironmentKey: string;
  tokenSecret: string;
  readyWhen: LysPredicate[];
}): LysContext {
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

export function signedOutContext(
  readyWhen: LysPredicate[],
  id = "signedOut",
): LysContext {
  return { id, title: "Signed-out user", mode: "uiFlow", prepare: [], readyWhen };
}

export function defineContract(contract: Omit<LysContract, "schemaVersion">): LysContract {
  return validateContract({ schemaVersion: 1, ...contract });
}

type NativeLysModule = {
  isTestSession(): boolean;
  credential(environmentKey: string): string | null;
};

let nativeModule: NativeLysModule | undefined;
function native(): NativeLysModule {
  nativeModule ??= requireNativeModule<NativeLysModule>("Lys");
  return nativeModule;
}

export const testSession = {
  isEnabled: () => native().isTestSession(),
  credential: (environmentKey: string) => native().credential(environmentKey),
};
