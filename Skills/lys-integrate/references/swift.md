# Swift integration

Add `Packages/LysSwift` as a Swift package dependency (product `Lys`) or use the published package
when available. Import `Lys` in the app/test tooling target.

## Semantics

```swift
let home = LysScreen(id: "home", title: "Home")
let quiz = LysScreen(id: "quiz.home", title: "Quiz")
let question = LysScreen(id: "quiz.question", title: "Question")
let openQuiz = LysAction(
  id: "home.openQuiz", title: "Open quiz", route: home, resultsIn: quiz,
  risk: .readOnly)
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

SwiftUI screen helpers use containment semantics so nested controls remain actionable. UIKit root
views receive a separate 1×1 accessibility marker; UIKit controls/labels can act as the marker
directly. Never make the entire UIKit screen one accessibility element.

## Authenticated setup

```swift
Lys.register(home)
Lys.register(quiz)
Lys.register(question)
Lys.register(openQuiz)
Lys.register(start)
Lys.configure(
  .init(bundleIdentifier: "com.example.app", entryRoutes: [home]))
Lys.register(
  .authenticated(
    id: "authenticated.student",
    title: "Authenticated student",
    tokenEnvironmentKey: "LYS_TEST_SESSION_TOKEN",
    tokenSecret: "test.student.session",
    readyWhen: [.route(home)]))

if let token = LysTestSession.credential(environmentKey: "LYS_TEST_SESSION_TOKEN") {
  await auth.restoreTestSession(token)
}
```

Keep the restore branch gated by `LysTestSession`; it returns values only for a host launch carrying
`-LysTesting`. The app owns token exchange/restore and must not log the value.

## Export and verify

Register screens/actions/contexts/flows once in a tooling or test target:

```swift
Lys.register(
  LysFlow(
    id: "quiz.complete", title: "Complete quiz", startRoute: quiz,
    entryRoutes: [home],
    steps: [.invoke(id: "quiz.start", title: "Start quiz", action: start)],
    acceptance: [.route(question)]))

try Lys.exportContract(to: repository.appending(path: ".lys/contract.json"))
```

Declare the real Home → Quiz action with `route: home` and `resultsIn: quiz`; export fails if no safe
path exists or if any step invokes an action from the wrong screen. `exportContract` automatically
adds every declared screen that can safely reach the flow start to its runtime entries, then
validates before writing. Add an export test and run `swift test`. For SDK changes,
also type-check all package sources against an iPhone Simulator SDK so UIKit code is compiled.
