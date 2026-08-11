# Swift integration

Add `Packages/LysSwift` as a Swift package dependency (product `Lys`) or use the published package
when available. Import `Lys` in the app/test tooling target.

## Semantics

```swift
QuizHome()
  .lysScreen("quiz.home", title: "Quiz")

Button("Start quiz", action: startQuiz)
  .lysAction(
    "quiz.start", title: "Start quiz", on: "quiz.home",
    resultsIn: "quiz.question", risk: .readOnly)

QuizProgressView()
  .lysState("quiz.progress", value: isComplete ? "complete" : "active")
```

SwiftUI screen helpers use containment semantics so nested controls remain actionable. UIKit root
views receive a separate 1×1 accessibility marker; UIKit controls/labels can act as the marker
directly. Never make the entire UIKit screen one accessibility element.

## Authenticated setup

```swift
Lys.register(
  .authenticated(
    id: "authenticated.student",
    title: "Authenticated student",
    tokenEnvironmentKey: "LYS_TEST_SESSION_TOKEN",
    tokenSecret: "test.student.session",
    readyWhen: [.route("home")]))

if let token = LysTestSession.credential(environmentKey: "LYS_TEST_SESSION_TOKEN") {
  await auth.restoreTestSession(token)
}
```

Keep the restore branch gated by `LysTestSession`; it returns values only for a host launch carrying
`-LysTesting`. The app owns token exchange/restore and must not log the value.

## Export and verify

Register screens/actions/contexts/flows once in a tooling or test target:

```swift
try Lys.exportContract(to: repository.appending(path: ".lys/contract.json"))
```

`exportContract` validates before writing. Add an export test and run `swift test`. For SDK changes,
also type-check all package sources against an iPhone Simulator SDK so UIKit code is compiled.
