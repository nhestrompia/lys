export type LysRisk = "readOnly" | "reversible" | "destructive" | "external";
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
    app?: {
        bundleIdentifier?: string;
        displayName?: string;
    };
    routes: LysScreen[];
    capabilities: LysAction[];
    contexts: LysContext[];
    flows: LysFlow[];
};
export declare class LysContractValidationError extends Error {
    constructor(message: string);
}
/** Validates the same cross-references and bounded-flow rules enforced by the Lys runner. */
export declare function validateContract(contract: LysContract): LysContract;
export declare function serializeContract(contract: LysContract): string;
export declare const route: (id: string) => LysPredicate;
export declare const visible: (identifier: string) => LysPredicate;
export declare const stateEquals: (id: string, value: string) => LysPredicate;
export declare function screen(id: string, title: string, terminal?: boolean): LysScreen;
export declare function action(id: string, title: string, options?: Omit<LysAction, "id" | "title" | "action" | "selector"> & {
    action?: LysActionKind;
    selector?: LysSelector;
}): LysAction;
export declare function screenProps(id: string): {
    readonly testID: `lys.screen.${string}`;
    readonly accessible: false;
    readonly collapsable: false;
};
export declare function actionProps(id: string): {
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
}): LysContext;
export declare function signedOutContext(readyWhen: LysPredicate[], id?: string): LysContext;
export declare function defineContract(contract: Omit<LysContract, "schemaVersion">): LysContract;
export declare const testSession: {
    isEnabled: () => boolean;
    credential: (environmentKey: string) => string | null;
};
//# sourceMappingURL=index.d.ts.map