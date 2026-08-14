# Expo and React Native integration

Add `@lys/testkit` and its Expo config plugin. Define semantics in a shared module imported by both
the app and export script so IDs and transitions cannot drift. Helpers accept the declared object:

```tsx
import {
  action, actionProps, application, flow, invoke, route, screen, screenProps, stateProps,
  testSession,
} from "@lys/testkit";

export const home = screen("home", "Home");
export const quizSetup = screen("quiz.setup", "Quiz setup");
export const quizQuestion = screen("quiz.question", "Quiz question");
export const quizResults = screen("quiz.results", "Quiz results", true);
export const homeOpenQuiz = action("home.openQuiz", "Open quiz", {
  route: home, resultsIn: quizSetup,
});
export const quizStart = action("quiz.start", "Start quiz", {
  route: quizSetup, resultsIn: quizQuestion,
});
export const app = application({
  bundleIdentifier: "com.example.app", entryRoutes: [home],
});

<View {...screenProps(home)}>
  <Pressable {...actionProps(homeOpenQuiz)} onPress={openQuiz} />
  <Text {...stateProps("quiz.progress", complete ? "complete" : "active")} />
</View>

const token = testSession.credential("LYS_TEST_SESSION_TOKEN");
if (testSession.resetRequestedFor("authenticated.student")) {
  // Use the app's real navigation API; Lys does not manipulate React Navigation directly.
  router.replace("/home");
}

export const startQuizFlow = flow({
  id: "quiz.start",
  title: "Start a quiz",
  startRoute: quizSetup,
  entryRoutes: [home],
  steps: [invoke("quiz.start", "Start quiz", quizStart)],
  acceptance: [route(quizQuestion)],
});
```

`screenProps` intentionally returns `accessible: false` and `collapsable: false`. Do not override it
with `accessible={true}`: React Native would group the screen and hide nested Pressables from XCTest.
Apply `actionProps` to the Pressable/TextInput/Switch itself, not its decorative card wrapper.
Controls may live below the initial `ScrollView` viewport; keep the semantic action on the real
control. Do not add fixed scroll actions to reach it—Lys reveals semantic controls automatically.

## Define and export

```ts
import { defineContract, route } from "@lys/testkit";
import { writeContract } from "@lys/testkit/node";

const contract = defineContract({ app, routes, capabilities, contexts, flows });
await writeContract(contract); // writes .lys/contract.json
```

`defineContract` and `writeContract` validate entry reachability and symbolically execute route
transitions through every step. They also expand each flow's entries with all known routes that can
safely reach its start, so a restored app can resume from Home or another declared screen without a
hand-maintained whitelist. A wrong-screen action fails export instead of failing in an agent
run. Type-check the
package, run the export script, parse the emitted JSON, and inspect an iOS accessibility snapshot.
Raw string IDs are rejected by semantic helpers. Put declarations in one shared module and import
the same objects from UI and export code; this prevents an instrumented button from being omitted
from the contract, as happened when separate handwritten lists drifted.
The `@lys/testkit/node` export is Node-safe and must work without mocking `expo-modules-core` or
patching Node's module loader. Treat either workaround as a broken SDK installation.

The native module exposes the test-session flag, requested context, reset marker, and requested
environment credential. Independent contexts default to `isolation: "relaunch"`; the host adds
`-LysReset` and `-LysContext <id>` before the next flow. Use `isolation: "preserve"` only for an
explicitly chained scenario. These markers are host-owned and cannot be supplied through session
`arguments`. Do not add general command execution, arbitrary storage access, or an automation
transport to the app.
