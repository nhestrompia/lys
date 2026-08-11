---
name: lys-integrate
description: Add or repair the minimal Lys semantic testing integration in Swift, SwiftUI, UIKit, Expo, or React Native apps. Use when an agent must expose stable screens, actions, observable state, authenticated test sessions, real UI-auth flows, bounded app flows, or generate and validate `.lys/contract.json` for deterministic Lys testing.
---

# Integrate Lys

Instrument the app's real controls and declare deterministic flows. Keep Lys as a small semantic
contract: do not add an in-app automation server, model-controlled selector layer, or test-only copy
of product navigation.

## Workflow

1. Inspect the app framework, navigation, auth bootstrap, and existing accessibility/test IDs.
2. Set the coverage scope before editing:
   - For a named outcome, trace its real entry screen, controls, repeated states, terminal state,
     and observable acceptance criteria from code.
   - For "integrate Lys", "test the app", or full-app coverage, inventory every reachable product
     destination and user action from navigation/router code. Build a coverage matrix and either
     declare a bounded flow for each requested outcome or report it as an explicit gap.
3. Reuse stable existing identifiers. Add Lys screen/action/state helpers only where semantics are
   missing. Never use localized display text as the primary selector when code can provide an ID.
4. Choose auth deliberately:
   - Use `authenticatedSession` to set up an identity for a gated product flow.
   - Use a separate `uiFlow` to test login itself.
   - Store only logical secret IDs in the contract; never write credentials or tokens to source.
5. Declare routes, capabilities, context, bounded steps, and at least one deterministic acceptance
   predicate. Put every secret referenced by flow steps in `requiredSecrets`.
6. Export `.lys/contract.json` using the SDK. Let SDK validation fail the task if IDs, references,
   loops, auth declarations, or acceptance criteria are invalid.
7. Run `node scripts/check-contract-goal.mjs <contract> "<user goal>"` from this skill for every
   named goal. A route or action without a matching bounded flow is exploratory-only and does not
   satisfy the request. For full-app coverage, run it once per row in the coverage matrix.
8. Run the app's ordinary tests, SDK compile/type-check, and a contract export test. Inspect the
   native accessibility tree when possible and confirm screen anchors do not hide child controls.
9. Report the exact flows added, auth mode, tests run, and every missing product semantic. Call the
   integration "full-app" only when the coverage matrix has no unreported rows.

## Framework routing

- For SwiftUI or UIKit, read [references/swift.md](references/swift.md).
- For Expo or React Native, read [references/expo.md](references/expo.md).
- For contract modeling, actions, predicates, auth, and completion rules, read
  [references/contract.md](references/contract.md).

## Guardrails

- Bind actions to the real button, input, switch, slider, or scroll surface.
- Keep screen containers from collapsing actionable descendants in the accessibility tree.
- Expose only non-sensitive state such as status, count, enum, progress, or result.
- Bound every repeat with `maximumIterations`; never infer completion from an agent response.
- Require every acceptance predicate to pass in the current run.
- Do not rebuild or relaunch when Lys can attach to the compatible running app.
- Do not add backward-compatibility aliases for pre-launch contract formats.
- Do not claim a flow works if only compilation or route entry was tested.
- Do not treat one successful flow as coverage for undeclared screens or outcomes.
