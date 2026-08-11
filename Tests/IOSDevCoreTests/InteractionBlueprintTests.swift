import Foundation
import Testing

@testable import IOSDevCore

@Test func checkedInBlueprintExampleLoadsAndCrossValidates() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let blueprint = try LysTestContract.load(
    from: repository.appending(path: "Examples/lys-contract.json"))

  #expect(blueprint.schemaVersion == 1)
  #expect(blueprint.flows.map(\.id) == ["auth.login", "quiz.complete"])
  #expect(blueprint.contexts?.first?.requiredSecrets == ["test.session"])
  #expect(blueprint.contexts?.first?.mode == .authenticatedSession)
  #expect(
    blueprint.contexts?.first?.session?.environment["LYS_TEST_SESSION_TOKEN"]?.secret
      == "test.session")
  #expect(
    blueprint.capabilities?.contains {
      $0.id == "home.openQuiz" && $0.route == "home" && $0.resultsIn == "quiz.setup"
    } == true)
}

@Test func blueprintRequiresDeterministicAcceptance() {
  let blueprint = InteractionBlueprint(
    routes: [
      .init(
        id: "home", title: "Home",
        match: [
          .init(kind: .visible, selector: .init(identifier: "home.title"))
        ])
    ],
    capabilities: [
      .init(
        id: "home.refresh", title: "Refresh", route: "home", action: .tap,
        selector: .init(identifier: "home.refresh"))
    ],
    flows: [
      .init(
        id: "home.check", title: "Check home", startRoute: "home",
        steps: [
          .init(
            id: "refresh", title: "Refresh", kind: .invoke,
            capability: "home.refresh")
        ], acceptance: [])
    ])

  #expect(throws: RPCError.self) { try blueprint.validate() }
}

@Test func blueprintRejectsUnknownTransitionRoutes() {
  let blueprint = InteractionBlueprint(
    routes: [
      .init(
        id: "home", title: "Home",
        match: [.init(kind: .visible, selector: .init(identifier: "home.title"))])
    ],
    capabilities: [
      .init(
        id: "home.open", title: "Open", route: "home", resultsIn: "missing",
        action: .tap, selector: .init(identifier: "home.open"))
    ],
    flows: [
      .init(
        id: "home.openFlow", title: "Open flow",
        steps: [
          .init(id: "open", title: "Open", kind: .invoke, capability: "home.open")
        ],
        acceptance: [.init(kind: .route, route: "home")])
    ])

  #expect(throws: RPCError.self) { try blueprint.validate() }
}

@Test func blueprintDiscoveryIsOptionalAndUsesOneCanonicalPath() throws {
  let root = FileManager.default.temporaryDirectory.appending(
    path: "lys-contract-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  #expect(try InteractionBlueprintDiscovery.load(in: root) == nil)
  #expect(InteractionBlueprintDiscovery.relativePath == ".lys/contract.json")
}

@Test func authenticatedContextRequiresAProtectedSessionEnvironment() {
  let contract = LysTestContract(
    routes: [
      .init(
        id: "home", title: "Home",
        match: [.init(kind: .visible, selector: .init(identifier: "home"))])
    ],
    contexts: [
      .init(
        id: "authenticated", title: "Authenticated", mode: .authenticatedSession,
        readyWhen: [.init(kind: .route, route: "home")])
    ],
    flows: [
      .init(
        id: "home.check", title: "Check home", context: "authenticated",
        steps: [.init(id: "home", title: "Reach home", kind: .navigate, route: "home")],
        acceptance: [.init(kind: .route, route: "home")])
    ])

  #expect(throws: RPCError.self) { try contract.validate() }
}

@Test func naturalLanguageSelectsOneDeclaredFlowWithoutAModel() {
  let flows = [
    BlueprintFlow(
      id: "auth.login", title: "Test sign in", description: "Authenticate a user",
      steps: [], acceptance: []),
    BlueprintFlow(
      id: "quiz.complete", title: "Complete a quiz", description: "Answer every quiz question",
      steps: [], acceptance: []),
  ]

  #expect(LysFlowMatcher.match(goal: "test the quiz", in: flows)?.id == "quiz.complete")
  #expect(LysFlowMatcher.match(goal: "verify sign in authentication", in: flows)?.id == "auth.login")
  #expect(LysFlowMatcher.match(goal: "test the app", in: flows) == nil)
}
