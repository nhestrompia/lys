# Operate interaction blueprints

Operate can test an app without repository integration. It observes the current accessibility tree,
creates screen-bound capability IDs, records state transitions in its App Graph, and lets the host
validate evidence. A blueprint is the optional deterministic layer for teams that want important
flows to run faster and identically with every agent model.

Place the file at `.operate/blueprint.json`. The version 1 schema is
[`Schemas/operate-blueprint.schema.json`](Schemas/operate-blueprint.schema.json), and a complete
authenticated quiz example is
[`Examples/operate-blueprint.json`](Examples/operate-blueprint.json).

## What a blueprint declares

- **Routes** are logical app states matched from visible, enabled, selected, text, value, progress,
  idle, and no-crash predicates. They are not source-code router names.
- **Capabilities** are things a user can do. A capability has a stable ID, selector, action, risk,
  optional origin route, and optional resulting route.
- **Contexts** prepare prerequisites such as an authenticated test account and prove readiness with
  deterministic predicates.
- **Flows** combine navigation, capability invocation, assertions, bounded loops, parameters, and
  terminal acceptance criteria.

`route` plus `resultsIn` turns capabilities into a route graph. A `navigate` step asks the host to
find and execute the shortest declared safe path. The agent never chooses intermediate buttons.
`repeatUntil` handles finite but data-dependent experiences—quizzes, onboarding pages, carts,
feeds, games, and multi-step forms—without one model call per iteration.

## Does an app need code changes?

No. Operate's zero-integration path remains the default, and a blueprint can target existing
accessibility identifiers, roles, names, text, and structural relationships. Native UIKit/SwiftUI,
React Native, Flutter, and hybrid apps all use the same host model once their controls are exposed
to iOS accessibility automation.

Adding stable accessibility identifiers is recommended for important or repeated flows. It is not
an Operate SDK dependency; it is the normal platform testing contract and improves VoiceOver too.
An app drawn as one opaque canvas, a game scene without accessibility nodes, or a custom control
that exposes neither semantics nor stable structure cannot be inferred reliably by any semantic
runner. Such apps need accessibility exposure or a future visual-gesture adapter; Operate fails
openly rather than pretending a screenshot proves interaction.

## Authentication and secrets

Blueprints contain secret IDs, never credentials:

```json
{
  "arguments": {
    "text": { "secret": "test.password" }
  }
}
```

Map each logical ID to a local Keychain account in `.iosdev/config.json`:

```json
{
  "schemaVersion": 1,
  "secrets": [
    { "environmentKey": "test.email", "keychainAccount": "learning-test-email" },
    { "environmentKey": "test.password", "keychainAccount": "learning-test-password" }
  ]
}
```

For source builds, a developer can populate the Keychain service used by Operate:

```sh
security add-generic-password -U -s com.operate.iosdev.flow-secrets -a learning-test-email -w
security add-generic-password -U -s com.operate.iosdev.flow-secrets -a learning-test-password -w
```

The password is requested interactively. It is never written to the blueprint, returned by an
agent tool, included in evidence, or placed in an agent prompt. CI may inject
`OPERATE_SECRET_TEST_EMAIL`-style environment values into `iosdevd`; Keychain takes precedence.

The context runs `prepare` only when `readyWhen` is false. This supports apps that preserve a valid
session, login screens, test tenant switching, first-run setup, and logout/login recovery.

## Parameters and source generation

Flow inputs are declared under `parameters`. A step can take a literal, a flow parameter, or a
secret. These are mutually exclusive:

```json
{
  "parameters": {
    "searchTerm": { "type": "string", "required": true }
  },
  "steps": [
    {
      "id": "search.fill",
      "title": "Enter search term",
      "kind": "invoke",
      "capability": "search.enterQuery",
      "arguments": { "text": { "parameter": "searchTerm" } }
    }
  ]
}
```

The blueprint is ordinary JSON Schema-validated source, so developers or coding agents can create
it directly, generate it from an app's route definitions or UI test DSL, and validate it in CI.
The public Swift `InteractionBlueprint` types also support generation with `JSONEncoder`. Operate
loads and cross-validates IDs, routes, contexts, selectors, loop budgets, and acceptance criteria
when a session is configured; invalid contracts stop before an agent can act.

Gesture capabilities use typed arguments declared on the capability: `swipe` accepts `direction`
(`up`, `down`, `left`, or `right`) and optional `durationMS`; `longPress` accepts duration in
seconds; `drag` requires `fromX`, `fromY`, `toX`, and `toY` fractions inside the resolved element;
and `setSlider` requires a `value` from 0 through 1. These are blueprint or flow data applied
relative to a uniquely host-resolved control. Agent tools never accept screen coordinates.

## Safety and completion

Every capability declares one of four risks: `readOnly`, `reversible`, `destructive`, or
`external`. Read-only and reversible test actions can run in a blueprint. Destructive and external
actions require a separate explicit user approval surface and currently fail closed; an agent
cannot add an argument that approves itself.

Every flow must have non-empty acceptance criteria. Completion records deterministic assertions,
a final stable screenshot, current-generation evidence, and a concise Done / Worked / Lacking
summary. Agent prose cannot override a failed assertion, exhausted loop, missing secret, crash, or
unreached terminal route.
