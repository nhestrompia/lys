import Foundation
import Testing
@testable import Lys

@Test func authenticatedContextUsesProtectedLaunchEnvironment() throws {
  let registry = LysRegistry()
  registry.configure(.init(bundleIdentifier: "com.example.app", displayName: "Example"))
  registry.register(.init(id: "home", title: "Home"))
  registry.register(
    .authenticated(
      id: "authenticated.user", title: "Authenticated user",
      tokenEnvironmentKey: "LYS_TEST_SESSION_TOKEN", tokenSecret: "test.session",
      readyWhen: [.route("home")]))
  registry.register(
    LysFlow(
      id: "home.check", title: "Check home", context: "authenticated.user",
      steps: [.init(id: "home", title: "Reach home", kind: .navigate, route: "home")],
      acceptance: [.route("home")]))

  let data = try registry.encodedContract()
  let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let contexts = try #require(json["contexts"] as? [[String: Any]])
  #expect(contexts.first?["mode"] as? String == "authenticatedSession")
}

@Test func registryEmitsStableSemanticIdentifiers() throws {
  let registry = LysRegistry()
  registry.register(LysScreen(id: "quiz.home", title: "Quiz"))
  registry.register(LysAction(id: "quiz.start", title: "Start quiz", route: "quiz.home"))
  let contract = registry.contract()
  #expect(contract.routes.first?.match.first?.selector?.identifier == "lys.screen.quiz.home")
  #expect(contract.capabilities.first?.selector.identifier == "lys.action.quiz.start")
  #expect(LysPredicate.state("quiz.progress", equals: "complete").equals == "complete")
}

@Test func registryRejectsBrokenCrossReferencesBeforeExport() {
  let registry = LysRegistry()
  registry.register(LysScreen(id: "home", title: "Home"))
  registry.register(
    LysAction(id: "open", title: "Open", route: "home", resultsIn: "missing"))
  registry.register(
    LysFlow(
      id: "home.open", title: "Open", startRoute: "home",
      steps: [.init(id: "open", title: "Open", kind: .invoke, capability: "open")],
      acceptance: [.route("home")]))

  #expect(throws: LysContractValidationError.self) { try registry.encodedContract() }
}

@Test func registryRequiresEveryFlowToBeBoundedAndDeterministic() {
  let contract = LysContract(
    routes: [LysScreen(id: "quiz", title: "Quiz")],
    capabilities: [LysAction(id: "answer", title: "Answer", route: "quiz")],
    flows: [
      LysFlow(
        id: "quiz.complete", title: "Complete quiz", startRoute: "quiz",
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
        steps: [.init(id: "home", title: "Home", kind: .navigate, route: "home")],
        acceptance: [.route("home")])
    ])

  #expect(throws: LysContractValidationError.self) { try contract.validate() }
}
