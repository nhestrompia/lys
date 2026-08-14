import Foundation
import Testing
@testable import Lys

@Test func authenticatedContextUsesProtectedLaunchEnvironment() throws {
  let registry = LysRegistry()
  registry.configure(
    .init(bundleIdentifier: "com.example.app", displayName: "Example", entryRoutes: ["home"]))
  registry.register(.init(id: "home", title: "Home"))
  registry.register(
    .authenticated(
      id: "authenticated.user", title: "Authenticated user",
      tokenEnvironmentKey: "LYS_TEST_SESSION_TOKEN", tokenSecret: "test.session",
      readyWhen: [.route("home")]))
  registry.register(
    LysFlow(
      id: "home.check", title: "Check home", context: "authenticated.user",
      startRoute: "home", entryRoutes: ["home"],
      steps: [.init(id: "home", title: "Reach home", kind: .navigate, route: "home")],
      acceptance: [.route("home")]))

  let data = try registry.encodedContract()
  let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let contexts = try #require(json["contexts"] as? [[String: Any]])
  #expect(contexts.first?["mode"] as? String == "authenticatedSession")
  #expect(contexts.first?["isolation"] as? String == "relaunch")
}

@Test func contextIsolationCanExplicitlyPreserveAChainedFlow() throws {
  let home = LysScreen(id: "home", title: "Home")
  let results = LysScreen(id: "results", title: "Results", terminal: true)
  let contract = LysContract(
    app: .init(entryRoutes: [home]),
    routes: [home, results],
    capabilities: [LysAction(id: "home.results", title: "Open results", route: home, resultsIn: results)],
    contexts: [
      LysContext(
        id: "chained", title: "Chained scenario", mode: .uiFlow,
        readyWhen: [.route(home)], isolation: .preserve)
    ],
    flows: [
      LysFlow(
        id: "results.check", title: "Check results", context: "chained", startRoute: home,
        entryRoutes: [home], steps: [.invoke(id: "open", title: "Open results", action: .init(
          id: "home.results", title: "Open results", route: home, resultsIn: results))],
        acceptance: [.route(results)])
    ])

  let data = try JSONDecoder().decode(LysContract.self, from: try JSONEncoder().encode(contract))
  #expect(data.contexts.first?.isolation == .preserve)
}

@Test func contextDecodingDefaultsMissingIsolationToRelaunch() throws {
  let context = try JSONDecoder().decode(
    LysContext.self,
    from: Data(
      #"{"id":"independent","title":"Independent","mode":"uiFlow","readyWhen":[{"kind":"route","route":"home"}]}"#
        .utf8))

  #expect(context.isolation == .relaunch)
  #expect(context.prepare.isEmpty)
}

@Test func authenticatedContextRejectsHostOwnedLaunchArguments() {
  let contract = LysContract(
    app: .init(entryRoutes: ["home"]), routes: [.init(id: "home", title: "Home")],
    contexts: [
      .init(
        id: "authenticated", title: "Authenticated", mode: .authenticatedSession,
        requiredSecrets: ["test.session"], readyWhen: [.route("home")],
        session: .init(
          environment: ["LYS_TOKEN": .secret("test.session")],
          arguments: ["-LysContext", "stale"]))
    ],
    flows: [
      .init(
        id: "home.check", title: "Check home", context: "authenticated", startRoute: "home",
        entryRoutes: ["home"],
        steps: [.init(id: "home", title: "Home", kind: .navigate, route: "home")],
        acceptance: [.route("home")])
    ])

  #expect(throws: LysContractValidationError.self) { try contract.validate() }
}

@Test func testSessionExposesOnlyHostLaunchSetupMarkers() {
  #expect(LysTestSession.isEnabled == ProcessInfo.processInfo.arguments.contains("-LysTesting"))
  #expect(
    LysTestSession.resetRequested
      == (LysTestSession.isEnabled && ProcessInfo.processInfo.arguments.contains("-LysReset")))
}

@Test func registryEmitsStableSemanticIdentifiers() throws {
  let registry = LysRegistry()
  let quiz = LysScreen(id: "quiz.home", title: "Quiz")
  registry.configure(.init(entryRoutes: [quiz.id]))
  registry.register(quiz)
  registry.register(LysAction(id: "quiz.start", title: "Start quiz", route: quiz))
  let contract = registry.contract()
  #expect(contract.routes.first?.match.first?.selector?.identifier == "lys.screen.quiz.home")
  #expect(contract.capabilities.first?.selector.identifier == "lys.action.quiz.start")
  #expect(LysPredicate.state("quiz.progress", equals: "complete").equals == "complete")
}

@Test func registryRejectsBrokenCrossReferencesBeforeExport() {
  let registry = LysRegistry()
  registry.configure(.init(entryRoutes: ["home"]))
  registry.register(LysScreen(id: "home", title: "Home"))
  registry.register(
    LysAction(id: "open", title: "Open", route: "home", resultsIn: "missing"))
  registry.register(
    LysFlow(
      id: "home.open", title: "Open", startRoute: "home", entryRoutes: ["home"],
      steps: [.init(id: "open", title: "Open", kind: .invoke, capability: "open")],
      acceptance: [.route("home")]))

  #expect(throws: LysContractValidationError.self) { try registry.encodedContract() }
}

@Test func registryRequiresEveryFlowToBeBoundedAndDeterministic() {
  let contract = LysContract(
    app: .init(entryRoutes: ["quiz"]),
    routes: [LysScreen(id: "quiz", title: "Quiz")],
    capabilities: [LysAction(id: "answer", title: "Answer", route: "quiz")],
    flows: [
      LysFlow(
        id: "quiz.complete", title: "Complete quiz", startRoute: "quiz",
        entryRoutes: ["quiz"],
        steps: [
          .init(
            id: "questions", title: "Questions", kind: .repeatUntil,
            until: .state("quiz.progress", equals: "complete"), maximumIterations: nil,
            steps: [.init(id: "answer", title: "Answer", kind: .invoke, capability: "answer")])
        ], acceptance: [.route("quiz")])
    ])

  #expect(throws: LysContractValidationError.self) { try contract.validate() }
}

@Test func authenticatedContextMustDeclareEverySecretItInjects() {
  let contract = LysContract(
    app: .init(entryRoutes: ["home"]),
    routes: [LysScreen(id: "home", title: "Home")],
    contexts: [
      LysContext(
        id: "authenticated", title: "Authenticated", mode: .authenticatedSession,
        readyWhen: [.route("home")],
        session: .init(environment: ["LYS_TOKEN": .secret("test.session")]))
    ],
    flows: [
      LysFlow(
        id: "home.check", title: "Check home", context: "authenticated",
        startRoute: "home", entryRoutes: ["home"],
        steps: [.init(id: "home", title: "Home", kind: .navigate, route: "home")],
        acceptance: [.route("home")])
    ])

  #expect(throws: LysContractValidationError.self) { try contract.validate() }
}

@Test func registryRejectsAFlowWhoseEntryCannotReachItsStart() {
  let contract = LysContract(
    app: .init(entryRoutes: ["home"]),
    routes: [LysScreen(id: "home", title: "Home"), LysScreen(id: "quiz", title: "Quiz")],
    capabilities: [LysAction(id: "start", title: "Start", route: "quiz")],
    flows: [
      LysFlow(
        id: "quiz.complete", title: "Complete quiz", startRoute: "quiz",
        entryRoutes: ["home"],
        steps: [.init(id: "start", title: "Start", kind: .invoke, capability: "start")],
        acceptance: [.route("quiz")])
    ])

  #expect(throws: LysContractValidationError.self) { try contract.validate() }
}

@Test func registryRejectsAnActionInvokedFromTheWrongScreen() {
  let home = LysScreen(id: "home", title: "Home")
  let quiz = LysScreen(id: "quiz", title: "Quiz")
  let contract = LysContract(
    app: .init(entryRoutes: ["home"]),
    routes: [home, quiz],
    capabilities: [LysAction(id: "quiz.start", title: "Start", route: quiz)],
    flows: [
      LysFlow(
        id: "quiz.complete", title: "Complete quiz", startRoute: home,
        entryRoutes: [home],
        steps: [.init(id: "start", title: "Start", kind: .invoke, capability: "quiz.start")],
        acceptance: [.route("home")])
    ])

  #expect(throws: LysContractValidationError.self) { try contract.validate() }
}

@Test func registryRejectsAFlowThatOmitsTheApplicationEntryScreen() {
  let home = LysScreen(id: "home", title: "Home")
  let quiz = LysScreen(id: "quiz", title: "Quiz")
  let contract = LysContract(
    app: .init(entryRoutes: [home]), routes: [home, quiz],
    flows: [
      LysFlow(
        id: "quiz.complete", title: "Complete quiz", startRoute: quiz,
        entryRoutes: [quiz],
        steps: [
          .init(
            id: "ready", title: "Quiz ready", kind: .assert,
            predicate: .route(quiz))
        ],
        acceptance: [.route(quiz)])
    ])

  #expect(throws: LysContractValidationError.self) { try contract.validate() }
}

@Test func registryExportsEverySafelyRecoverableFlowEntry() throws {
  let onboarding = LysScreen(id: "onboarding", title: "Onboarding")
  let home = LysScreen(id: "home", title: "Home")
  let quiz = LysScreen(id: "quiz", title: "Quiz")
  let contract = LysContract(
    app: .init(entryRoutes: [onboarding]), routes: [onboarding, home, quiz],
    capabilities: [
      LysAction(
        id: "onboarding.finish", title: "Finish onboarding", route: onboarding,
        resultsIn: home),
      LysAction(id: "home.quiz", title: "Open quiz", route: home, resultsIn: quiz),
    ],
    flows: [
      LysFlow(
        id: "quiz.open", title: "Open quiz", startRoute: quiz,
        entryRoutes: [onboarding],
        steps: [
          .init(
            id: "ready", title: "Quiz ready", kind: .assert,
            predicate: .route(quiz))
        ],
        acceptance: [.route(quiz)])
    ])

  let expanded = contract.expandingRecoverableFlowEntries()
  #expect(expanded.flows[0].entryRoutes == ["onboarding", "home", "quiz"])
  try expanded.validate()
}
