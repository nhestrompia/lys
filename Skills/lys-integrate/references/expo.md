# Expo and React Native integration

Add `@lys/testkit` and its Expo config plugin. Use helpers on real React Native nodes:

```tsx
import { actionProps, screenProps, stateProps, testSession } from "@lys/testkit";

<View {...screenProps("quiz.home")}>
  <Pressable {...actionProps("quiz.start")} onPress={startQuiz} />
  <Text {...stateProps("quiz.progress", complete ? "complete" : "active")} />
</View>

const token = testSession.credential("LYS_TEST_SESSION_TOKEN");
```

`screenProps` intentionally returns `accessible: false` and `collapsable: false`. Do not override it
with `accessible={true}`: React Native would group the screen and hide nested Pressables from XCTest.
Apply `actionProps` to the Pressable/TextInput/Switch itself, not its decorative card wrapper.

## Define and export

```ts
import { defineContract, route } from "@lys/testkit";
import { writeContract } from "@lys/testkit/node";

const contract = defineContract({ routes, capabilities, contexts, flows });
await writeContract(contract); // writes .lys/contract.json
```

`defineContract` and `writeContract` validate cross-references and bounded execution. Type-check the
package, run the export script, parse the emitted JSON, and inspect an iOS accessibility snapshot.

The native module exposes only the test-session flag and requested environment credential. Do not
add general command execution, arbitrary storage access, or an automation transport to the app.
