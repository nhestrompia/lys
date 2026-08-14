---
name: lys-integrate
description: Add, audit, migrate, or repair a production-quality Lys semantic testing integration in Swift, SwiftUI, UIKit, Expo, or React Native apps. Use when an agent must install or upgrade a Lys SDK, expose stable screens/actions/state, model reachable navigation, support authenticated test sessions or login testing, create bounded flows, export `.lys/contract.json`, diagnose Lys route/action failures, or prove that a requested app journey works from real application entry states.
---

# Integrate Lys

Model the real product UI as a small, typed semantic graph. Lys owns deterministic execution and
evidence; the app owns navigation, authentication, and state. Do not build an in-app automation
server, model-controlled selector layer, or test-only copy of product navigation.

Read [references/contract.md](references/contract.md) before changing a contract. Also read the
applicable framework guide: [references/expo.md](references/expo.md) or
[references/swift.md](references/swift.md).

## Non-negotiable invariants

1. Define every screen and action once in shared typed code. Import the same objects into the UI and
   contract exporter. Never maintain a second handwritten list or pass copied string IDs.
2. Set `app.entryRoutes` to the guaranteed bootstrap/restoration states that must be statically
   covered. A flow's own start route is not a substitute. SDK export and host loading also derive
   every additional declared route that can safely reach the flow start.
3. Model every safe entry transition as a real capability with `route` and `resultsIn`. Bind it to
   the actual interactive control, not a label, card wrapper, or guessed coordinate.
   Controls inside scroll containers remain semantic actions; do not encode viewport-dependent
   scroll counts into the flow. The host reveals them with bounded semantic scrolling.
4. Make every requested flow reachable from every supported entry route, directly or through its
   declared context. Let SDK validation prove this before running an agent.
5. Start flow steps at `flow.startRoute`. Entry navigation is host-owned graph traversal; do not
   repeat those navigation capabilities in the flow body.
6. Bound every repeat and verify a terminal, user-observable result. Opening the first screen or an
   agent ending its turn is not completion.
7. Keep secrets out of code, contracts, prompts, logs, and evidence. Use logical secret IDs.

## Required workflow

### 1. Establish the actual integration state

- Inspect the package manifest, lockfile, installed module, and local/published artifact. Confirm the
  app is compiling against the intended Lys version; a changed local tarball requires a new version
  and clean reinstall.
- Inspect bootstrap, router/navigation definitions, auth restoration, tabs/deep links, and the real
  event handlers. Do not infer the graph from the existing contract alone.
- Inspect the current `.lys/contract.json` and exporter, then compare them with the live UI code.
  Treat missing controls, stale IDs, or duplicate declaration sources as defects.
- Ask the host for the currently observed route. Never defer a route that is visible during the
  requested test as a future coverage gap when the graph already contains a safe path from it.
- For broad integration, create a coverage matrix before editing:

| Goal | App/context entries | Path to start | Flow start | Bounded work | Terminal result |
|---|---|---|---|---|---|

Do not silently omit a requested or reachable product outcome.

### 2. Create one semantic source of truth

- Declare shared screen objects for stable, mutually exclusive observable states.
- Declare shared action objects for real controls. Include `route` and `resultsIn` whenever the
  action changes screen.
- Reuse existing stable accessibility/test IDs when valid; otherwise add Lys helpers.
- Add minimal non-sensitive state markers only for values needed by acceptance or loop termination.
- In Expo/React Native, import the shared objects into both components and the Node exporter.
- In Swift, register the same `LysScreen` and `LysAction` values used by view modifiers.

Never edit generated `.lys/contract.json` as the source of truth.

### 3. Model startup and authentication

- Declare every real attachment state in `app.entryRoutes`, including signed-out and restored states
  when both are possible.
- Use `authenticatedSession` to prepare identity for testing a gated product flow.
- Use a separate `uiFlow` to test login/logout UI itself.
- Make UI preparation recover from every application entry. An authenticated context may normalize
  state through a host-owned relaunch and must declare route-based `readyWhen`.
- Declare context `isolation` when a flow has special lifecycle needs. `relaunch` is the default for
  independent flows and preserves app data; `preserve` is only for intentionally chained flows.
  On a relaunch, the host sends `-LysReset` and `-LysContext <id>` so the app's own router/session
  setup can establish `readyWhen`. These markers and `-LysTesting` are host-owned; never put them
  in session `arguments`.
- Declare all referenced logical secrets in `requiredSecrets`.

### 4. Build the navigation graph

- Trace each supported entry to the flow start through actual controls.
- Give every graph edge one unambiguous source route and observable destination route.
- Add destination screen instrumentation before claiming `resultsIn`.
- Exclude destructive or external actions from automatic entry navigation.
- Model modal dismissal, back navigation, tabs, and deep links only when they are safe and actually
  supported from the declared source state.
- Reject ambiguous screen markers: exactly one declared route must match at a time.

### 5. Declare the bounded flow

- Set `startRoute`, supported `entryRoutes`, optional context, parameters, and logical secrets.
- Begin steps in the state represented by `startRoute`; the host reaches it through the graph.
- Use `repeatUntil` with a stable terminal predicate and realistic `maximumIterations` for dynamic
  lists, quizzes, onboarding pages, pagination, and other repeated work.
- Make branchable controls deterministic through observable state or bounded alternatives; do not
  ask the model to guess the next action.
- Require acceptance predicates for the final route/result, completion state, and any requested
  business outcome. Prefer state/route assertions over pixels or localized text.

### 6. Export and statically audit

- Export with the SDK and fail the task on validation errors. Never weaken validation to make an
  incomplete graph export.
- Run:

```sh
node Skills/lys-integrate/scripts/check-contract-goal.mjs \
  .lys/contract.json "<user goal>" --current-route "<observed route>"
```

- Run it once per coverage-matrix row for broad integration.
- Type-check/compile the SDK integration, run the contract export test, and parse the emitted JSON.
- Confirm the emitted package/schema version and verify all shared UI actions expected by the
  requested paths appear in `capabilities`.
- Confirm the exported flow entries include routes automatically recoverable through safe graph
  paths. Do not manually duplicate that derived list.

### 7. Prove the real journey

Static validation proves graph consistency, not product behavior. For every requested flow:

1. Start from each supported application/context entry state.
2. Run the host-owned flow without manually pre-positioning the app.
3. Confirm every graph edge delivers its control and observes its declared destination.
4. Exercise all bounded iterations and reach the terminal result.
5. Confirm every acceptance predicate uses fresh evidence from this run.
6. Inspect the iOS accessibility tree when possible. Confirm screen containers do not hide nested
   controls and duplicate labels remain individually addressable.
7. Confirm ordinary manual taps, typing, and scrolling still work while no agent action is active.

Do not report success after only compilation, export, route entry, or partial flow execution.

## Repair failures by cause

- **No transition path:** compare router/UI source with exported capabilities. Add the missing real
  control and `route` → `resultsIn` edge; do not retry the same invalid contract.
- **Flow excludes current route:** add a safe path and supported entry, or add a context that truly
  normalizes the state. Do not merely list an unreachable entry.
- **Flow starts on the previous terminal screen:** keep the previous evidence, then normalize before
  the next flow. Use the context's default `relaunch` policy and implement the app-owned
  `LysTestSession`/`testSession` setup branch; do not add an artificial cleanup route solely for
  testing.
- **Exploratory run starts from stale UI:** a new exploratory journey also receives `-LysReset`
  without a context ID. Reset to the app's default entry route; keep state only while continuing
  the same journey with its `journeyID`.
- **Action missing:** first distinguish absent from off-screen. Inspect the full accessibility tree
  and scroll containers. Bind `actionProps`/`.lysAction` to the actual control and verify the
  installed SDK/exporter uses the same shared object. Do not add fixed scroll steps merely because
  a valid control starts below the viewport.
- **Action delivered, destination absent:** inspect the handler, async loading/error states, and
  destination screen marker. Fix product behavior or model the real intermediate route.
- **Wrong-route action:** remove entry-navigation actions from the flow body or fix the preceding
  step's declared result.
- **Ambiguous route:** make route predicates mutually exclusive; do not let the runtime choose.
- **Loop stops early or continues after completion:** use stable progress/terminal state and correct
  `repeatUntil`; never infer completion from navigation labels or agent commentary.
- **Contract and UI disagree:** remove duplicate declaration lists and migrate to shared objects.
- **Unexpected old behavior:** inspect the lockfile and installed package; bump/repack/reinstall the
  SDK artifact rather than overwriting a tarball at the same version.

After a repair, rerun static audit and the complete journey from its original failing entry state.

## Definition of done

- Intended SDK version is installed and locked.
- Shared semantic declarations compile in both UI and exporter code.
- All requested application entry states are modeled.
- Every requested goal uniquely matches a bounded flow.
- Every supported entry has a validated safe path to the flow start.
- Contract export and `check-contract-goal.mjs` pass.
- The real host-owned journey reaches its terminal result from every supported entry.
- Accessibility delivery, acceptance evidence, and ordinary manual interaction are verified.
- Final report states: flows added/repaired, auth mode, entries tested, terminal results, commands
  run, and any remaining coverage gaps. Call coverage “full-app” only when the matrix has no gaps.

## Guardrails

- Do not select by localized display text when code can expose a stable ID.
- Do not make an entire screen one accessibility element.
- Do not expose credentials, arbitrary storage, command execution, or an automation transport.
- Do not rebuild/relaunch when Lys can attach to the compatible running app, except for a declared
  context (or default independent-flow policy) that intentionally normalizes startup.
- Do not add backward-compatibility aliases for pre-launch formats.
- Do not describe exploratory action discovery as deterministic flow verification.
