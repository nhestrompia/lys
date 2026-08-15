# Lys SDK

Lys provides a small semantic test contract for Swift and Expo/React Native applications. The SDK
does not boot devices, execute arbitrary code, take screenshots, or decide test results. It adds
stable screen/action identifiers and generates `.lys/contract.json`; the Lys desktop runner owns
physical input, bounded flow execution, evidence, cancellation, and verification.

## Monorepo packages

- `Packages/LysSwift`: standalone Swift package, product `Lys`; stable releases mirror this subtree
  to the `lys-swift` repository so the SDK retains its iOS 15 and macOS 13 deployment targets.
- `Packages/LysExpo`: Expo module and TypeScript helpers, package `@nhestrompia/lys`.
- `Schemas/lys-test-contract.schema.json`: shared versioned wire contract.
- `Examples/lys-contract.json`: authenticated-session and UI-auth flow example.

## Authentication modes

Use `authenticatedSession` when authentication is setup for another flow. Lys resolves a logical
secret from the macOS Keychain, terminates the current app process, and relaunches the same installed
build with `-LysTesting` and `SIMCTL_CHILD_` environment values. Agents see only the secret ID.

```swift
Lys.register(
  .authenticated(
    id: "authenticated.student",
    title: "Authenticated student",
    tokenEnvironmentKey: "LYS_TEST_SESSION_TOKEN",
    tokenSecret: "test.student.session",
    readyWhen: [.route("home")]
  )
)
```

The app explicitly opts into restoring that test identity:

```swift
if let token = LysTestSession.credential(environmentKey: "LYS_TEST_SESSION_TOKEN") {
  await auth.restoreTestSession(token)
}
```

Use `uiFlow` when authentication itself is under test. Its steps type protected email/password
values into the real controls and assert the post-login screen. The checked-in example demonstrates
both modes. Production builds should not restore test credentials; `LysTestSession` returns values
only when the host supplied `-LysTesting`.

## Between-flow setup and isolation

Independent flows are normalized before they start. Contexts default to `isolation: .relaunch` in
Swift or `isolation: "relaunch"` in Expo/React Native. The host terminates and relaunches the app
without erasing app data, then supplies `-LysTesting -LysReset -LysContext <context-id>`.
These markers are host-owned; do not add them to authenticated-session `arguments`. Ordinary app
launch arguments remain supported.

The app owns its router and session setup. After restoring the requested identity, inspect the
context marker and reset to the route represented by `readyWhen`:

```swift
if LysTestSession.resetRequested(for: "authenticated.student") {
  router.reset(to: .home)
}
```

```tsx
if (testSession.resetRequestedFor("authenticated.student")) {
  router.replace("/home");
}
```

For exploratory runs without a declared context, use the generic reset marker and your app's
default entry route (`LysTestSession.resetRequested` / `testSession.resetRequested()`). Continuing
an existing journey with its `journeyID` intentionally does not reset between individual steps.

Use `isolation: .preserve` / `isolation: "preserve"` only for an explicitly chained scenario.
Do not navigate away from a terminal screen when a flow finishes; that screen and its evidence stay
available until the host prepares the next flow. A real Home/back capability should still be
declared when it is part of the product UI, but it is not a substitute for setup normalization.

## SwiftUI integration

```swift
import Lys

let quiz = LysScreen(id: "quiz.home", title: "Quiz")
let question = LysScreen(id: "quiz.question", title: "Question")
let start = LysAction(
  id: "quiz.start", title: "Start quiz", route: quiz, resultsIn: question,
  risk: .readOnly)

QuizHome()
  .lysScreen(quiz)

Button("Start quiz", action: startQuiz)
  .lysAction(start)

QuizProgressView()
  .lysState("quiz.progress", value: isComplete ? "complete" : "active")
```

Register contexts and flows once during application/test setup, then export the generated contract:

```swift
try Lys.exportContract(to: repository.appending(path: ".lys/contract.json"))
```

Export validates IDs, entry reachability, every step's route state, bounded loops, secret
declarations, and acceptance criteria. A
malformed contract fails in the developer's tooling target before Lys can run it.

## Expo integration

Add `@nhestrompia/lys` and its config plugin, then spread the generated semantic props onto real React
Native controls:

```tsx
import {
  action, actionProps, application, screen, screenProps, stateProps, testSession,
} from "@nhestrompia/lys";

const home = screen("home", "Home");
const quizSetup = screen("quiz.setup", "Quiz setup");
const openQuiz = action("home.openQuiz", "Open quiz", {
  route: home, resultsIn: quizSetup,
});
const app = application({
  bundleIdentifier: "com.example.app", entryRoutes: [home],
});

<View {...screenProps(home)}>
  <Pressable {...actionProps(openQuiz)} onPress={navigateToQuiz} />
  <Text {...stateProps("quiz.progress", isComplete ? "complete" : "active")} />
</View>

const token = testSession.credential("LYS_TEST_SESSION_TOKEN");
```

Define the contract in TypeScript and export it from a Node script or test setup:

```ts
import { defineContract } from "@nhestrompia/lys";
import { writeContract } from "@nhestrompia/lys/node";

const contract = defineContract({ app, routes, capabilities, contexts, flows });
await writeContract(contract); // .lys/contract.json
```

The Node export does not load `expo-modules-core`; do not mock the module or patch Node's loader.
Only `testSession` lazily resolves the native bridge inside the running Expo app.

The native Expo module only exposes the test-session flag and a requested launch credential. It
contains no general command or automation channel.

`screenProps` deliberately keeps the container non-accessible and non-collapsible: the screen
anchor stays discoverable while nested Pressables remain separate actionable elements. Do not add
`accessible={true}` to a screen root. `actionProps` belongs on the real Pressable or control.
Semantic helpers require the shared screen/action object, not a copied string ID. Import the same
declarations in the UI and export script so an instrumented navigation control cannot be omitted.

## Contract rules

- IDs are dot-separated and stable across builds.
- Actions bind to real UI controls; the host still sends physical input.
- Every flow has non-empty bounded steps and acceptance criteria.
- `app.entryRoutes` declares guaranteed bootstrap/restoration roots that must always work.
- Every flow declares `startRoute` and guaranteed `entryRoutes`; SDK export and host loading add all
  other declared routes that can safely reach the start through `route` → `resultsIn` capabilities.
- SDK export symbolically executes every step and rejects actions invoked from the wrong route.
- Every acceptance criterion must pass in the current evidence generation.
- Loops require a maximum iteration count.
- Destructive/external actions require host approval.
- Authenticated setup and UI authentication are separate flows.
- A model ending its response never marks a flow complete.
- Runs without a Lys contract are exploratory and cannot become trusted green verification.
- Partial contracts remain partial: an unmatched goal may be explored, but only a uniquely matched
  declared flow can produce trusted verification.

For every outcome promised by an integration, audit the emitted contract:

```sh
node Skills/lys-integrate/scripts/check-contract-goal.mjs .lys/contract.json "test numbers"
```

Exit 0 means one declared flow covers the goal. Route/action-only coverage is exploratory; missing
semantics or ambiguous matches fail with a nonzero exit. A general "test the app" integration must
first inventory the app router/navigation destinations and run the audit for every coverage row.

## Verification

```sh
./Scripts/test-local.sh
swift test --package-path Packages/LysSwift
npm run check:expo-sdk
```
