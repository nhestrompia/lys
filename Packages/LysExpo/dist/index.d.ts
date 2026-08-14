export type LysRisk = "readOnly" | "reversible" | "destructive" | "external";
export type LysIsolationPolicy = "relaunch" | "preserve";
export type LysActionKind = "tap" | "doubleTap" | "longPress" | "type" | "clear" | "toggle" | "select" | "scrollUp" | "scrollDown" | "swipe" | "drag" | "setSlider" | "dismiss" | "back";
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
    kind: "route" | "visible" | "absent" | "enabled" | "selected" | "value" | "text" | "progressComplete" | "appIdle" | "noCrash";
    route?: string;
    selector?: LysSelector;
    equals?: string;
    matches?: string;
};
export type LysInput = {
    literal: string;
} | {
    parameter: string;
} | {
    secret: string;
};
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
    isolation?: LysIsolationPolicy;
    requiredSecrets?: string[];
    startRoute?: string;
    entryRoutes?: string[];
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
    startRoute: string;
    entryRoutes: string[];
    parameters?: LysAction["parameters"];
    requiredSecrets?: string[];
    steps: LysStep[];
    acceptance: LysPredicate[];
};
export type LysApplication = {
    bundleIdentifier?: string;
    displayName?: string;
    entryRoutes: string[];
};
export type LysContract = {
    $schema?: string;
    schemaVersion: 2;
    app: LysApplication;
    routes: LysScreen[];
    capabilities: LysAction[];
    contexts: LysContext[];
    flows: LysFlow[];
};
export declare class LysContractValidationError extends Error {
    constructor(message: string);
}
/**
 * Expands developer-declared coverage roots with every known route that can safely reach each
 * flow's start. This keeps a restored/running app usable without requiring developers to predict
 * every screen on which a user might leave it.
 */
export declare function expandRecoverableEntries(contract: LysContract): LysContract;
/** Validates the same cross-references and bounded-flow rules enforced by the Lys runner. */
export declare function validateContract(contract: LysContract): LysContract;
export declare function serializeContract(contract: LysContract): string;
type LysReference<T extends {
    id: string;
}> = Pick<T, "id">;
export declare const route: (reference: LysReference<LysScreen>) => LysPredicate;
export declare const visible: (identifier: string) => LysPredicate;
export declare const stateEquals: (id: string, value: string) => LysPredicate;
export declare function screen(id: string, title: string, terminal?: boolean): LysScreen;
export declare function action(id: string, title: string, options?: Omit<LysAction, "id" | "title" | "action" | "selector" | "route" | "resultsIn"> & {
    action?: LysActionKind;
    selector?: LysSelector;
    route?: LysReference<LysScreen>;
    resultsIn?: LysReference<LysScreen>;
}): LysAction;
export declare function flow(options: Omit<LysFlow, "startRoute" | "entryRoutes"> & {
    startRoute: LysReference<LysScreen>;
    entryRoutes: LysReference<LysScreen>[];
}): LysFlow;
export declare function navigate(id: string, title: string, destination: LysReference<LysScreen>): LysStep;
export declare function invoke(id: string, title: string, capability: LysReference<LysAction>, options?: Omit<LysStep, "id" | "title" | "kind" | "capability">): LysStep;
export declare function uiContext(options: {
    id: string;
    title: string;
    startRoute: LysReference<LysScreen>;
    entryRoutes: LysReference<LysScreen>[];
    prepare: LysStep[];
    readyWhen: LysPredicate[];
    requiredSecrets?: string[];
    isolation?: LysIsolationPolicy;
}): LysContext;
export declare function application(options: {
    bundleIdentifier?: string;
    displayName?: string;
    entryRoutes: LysReference<LysScreen>[];
}): LysApplication;
export declare function screenProps(reference: LysReference<LysScreen>): {
    readonly testID: `lys.screen.${string}`;
    readonly accessible: false;
    readonly collapsable: false;
};
export declare function actionProps(reference: LysReference<LysAction>): {
    readonly testID: `lys.action.${string}`;
    readonly accessible: true;
};
export declare function stateProps(id: string, value: string | number | boolean): {
    readonly testID: `lys.state.${string}`;
    readonly accessible: true;
    readonly accessibilityValue: {
        readonly text: string;
    };
};
export declare function authenticatedContext(options: {
    id: string;
    title: string;
    tokenEnvironmentKey: string;
    tokenSecret: string;
    readyWhen: LysPredicate[];
    isolation?: LysIsolationPolicy;
}): LysContext;
export declare function signedOutContext(readyWhen: LysPredicate[], id?: string, isolation?: LysIsolationPolicy): LysContext;
export declare function defineContract(contract: Omit<LysContract, "schemaVersion">): LysContract;
export declare const testSession: {
    isEnabled: () => boolean;
    credential: (environmentKey: string) => string | null;
    contextID: () => string | null;
    resetRequested: () => boolean;
    resetRequestedFor: (contextID: string) => boolean;
};
export {};
//# sourceMappingURL=index.d.ts.map