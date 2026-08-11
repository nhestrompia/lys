# Lys SDK

Lys provides a small semantic test contract for Swift and Expo/React Native applications. The SDK
does not boot devices, execute arbitrary code, take screenshots, or decide test results. It adds
stable screen/action identifiers and generates `.lys/contract.json`; the Lys desktop runner owns
physical input, bounded flow execution, evidence, cancellation, and verification.

## Monorepo packages

- `Packages/LysSwift`: standalone Swift package, product `Lys`.
- `Packages/LysExpo`: Expo module and TypeScript helpers, package `@lys/testkit`.
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

## SwiftUI integration

```swift
import Lys

QuizHome()
  .lysScreen("quiz.home", title: "Quiz")

Button("Start quiz", action: startQuiz)
  .lysAction(
    "quiz.start", title: "Start quiz", on: "quiz.home",
    resultsIn: "quiz.question", risk: .readOnly
  )

QuizProgressView()
  .lysState("quiz.progress", value: isComplete ? "complete" : "active")
```

Register contexts and flows once during application/test setup, then export the generated contract:

```swift
try Lys.exportContract(to: repository.appending(path: ".lys/contract.json"))
```

Export validates IDs, references, bounded loops, secret declarations, and acceptance criteria. A
malformed contract fails in the developer's tooling target before Lys can run it.

## Expo integration

Add `@lys/testkit` and its config plugin, then spread the generated semantic props onto real React
Native controls:

```tsx
import { actionProps, screenProps, stateProps, testSession } from "@lys/testkit";

<View {...screenProps("quiz.home")}>
  <Pressable {...actionProps("quiz.start")} onPress={startQuiz} />
  <Text {...stateProps("quiz.progress", isComplete ? "complete" : "active")} />
</View>

const token = testSession.credential("LYS_TEST_SESSION_TOKEN");
```

Define the contract in TypeScript and export it from a Node script or test setup:

```ts
import { defineContract } from "@lys/testkit";
import { writeContract } from "@lys/testkit/node";

const contract = defineContract({ routes, capabilities, contexts, flows });
await writeContract(contract); // .lys/contract.json
```

The native Expo module only exposes the test-session flag and a requested launch credential. It
contains no general command or automation channel.

`screenProps` deliberately keeps the container non-accessible and non-collapsible: the screen
anchor stays discoverable while nested Pressables remain separate actionable elements. Do not add
`accessible={true}` to a screen root. `actionProps` belongs on the real Pressable or control.

## Contract rules

- IDs are dot-separated and stable across builds.
- Actions bind to real UI controls; the host still sends physical input.
- Every flow has non-empty bounded steps and acceptance criteria.
- Every acceptance criterion must pass in the current evidence generation.
- Loops require a maximum iteration count.
- Destructive/external actions require host approval.
- Authenticated setup and UI authentication are separate flows.
- A model ending its response never marks a flow complete.
- Runs without a Lys contract are exploratory and cannot become trusted green verification.

## Verification

```sh
./Scripts/test-local.sh
swift test --package-path Packages/LysSwift
npm run check:expo-sdk
```
