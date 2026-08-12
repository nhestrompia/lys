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

  #expect(blueprint.schemaVersion == 2)
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
  let quiz = try #require(blueprint.flows.first { $0.id == "quiz.complete" })
  #expect(quiz.startRoute == "quiz.setup")
  #expect(quiz.entryRoutes == ["home", "auth.login", "quiz.setup"])
}

@Test func earlyV2ContractWithoutAppEntryRoutesGetsActionableValidationError() throws {
  let contract = """
    {
      "schemaVersion": 2,
      "app": { "displayName": "Early v2" },
      "routes": [],
      "capabilities": [],
      "contexts": [],
      "flows": []
    }
    """
  let url = FileManager.default.temporaryDirectory
    .appending(path: "lys-missing-entry-\(UUID().uuidString).json")
  try Data(contract.utf8).write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }

  do {
    _ = try InteractionBlueprint.load(from: url)
    Issue.record("Expected the incomplete v2 contract to fail validation")
  } catch let error as RPCError {
    #expect(error.message.contains("app.entryRoutes"))
  }
}

@Test func blueprintRequiresDeterministicAcceptance() {
  let blueprint = InteractionBlueprint(
    app: .init(entryRoutes: ["home"]),
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
        id: "home.check", title: "Check home", startRoute: "home", entryRoutes: ["home"],
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
    app: .init(entryRoutes: ["home"]),
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
        id: "home.openFlow", title: "Open flow", startRoute: "home",
        entryRoutes: ["home"],
        steps: [
          .init(id: "open", title: "Open", kind: .invoke, capability: "home.open")
        ],
        acceptance: [.init(kind: .route, route: "home")])
    ])

  #expect(throws: RPCError.self) { try blueprint.validate() }
}

@Test func blueprintRejectsUnreachableFlowEntryBeforeTheAgentRuns() {
  let home = BlueprintRoute(
    id: "home", title: "Home",
    match: [.init(kind: .visible, selector: .init(identifier: "lys.screen.home"))])
  let setup = BlueprintRoute(
    id: "quiz.setup", title: "Quiz setup",
    match: [.init(kind: .visible, selector: .init(identifier: "lys.screen.quiz.setup"))])
  let start = BlueprintCapability(
    id: "quiz.start", title: "Start", route: "quiz.setup", action: .tap,
    selector: .init(identifier: "lys.action.quiz.start"))
  let contract = InteractionBlueprint(
    app: .init(entryRoutes: ["home"]),
    routes: [home, setup], capabilities: [start],
    flows: [
      .init(
        id: "quiz.complete", title: "Complete quiz", startRoute: "quiz.setup",
        entryRoutes: ["home"],
        steps: [.init(id: "start", title: "Start", kind: .invoke, capability: "quiz.start")],
        acceptance: [.init(kind: .route, route: "quiz.setup")])
    ])

  #expect(throws: RPCError.self) { try contract.validate() }
}

@Test func navigationPlannerFindsDeclaredRouteToFlowStart() {
  let openQuiz = BlueprintCapability(
    id: "home.openQuiz", title: "Open quiz", route: "home", resultsIn: "quiz.setup",
    action: .tap, selector: .init(identifier: "lys.action.home.openQuiz"))
  let path = BlueprintNavigationPlanner.path(
    from: "home", to: "quiz.setup", capabilities: [openQuiz])

  #expect(path?.map(\.id) == ["home.openQuiz"])
}

@Test func runtimeExpandsFlowEntriesToEverySafelyRecoverableKnownRoute() throws {
  let blueprint = InteractionBlueprint(
    app: .init(entryRoutes: ["onboarding"]),
    routes: [
      .init(
        id: "onboarding", title: "Onboarding",
        match: [.init(kind: .visible, selector: .init(identifier: "screen.onboarding"))]),
      .init(
        id: "home", title: "Home",
        match: [.init(kind: .visible, selector: .init(identifier: "screen.home"))]),
      .init(
        id: "quiz", title: "Quiz",
        match: [.init(kind: .visible, selector: .init(identifier: "screen.quiz"))]),
    ],
    capabilities: [
      .init(
        id: "onboarding.finish", title: "Finish onboarding", route: "onboarding",
        resultsIn: "home", action: .tap,
        selector: .init(identifier: "action.onboarding.finish"), risk: .reversible),
      .init(
        id: "home.openQuiz", title: "Open quiz", route: "home", resultsIn: "quiz",
        action: .tap, selector: .init(identifier: "action.home.quiz"), risk: .readOnly),
    ],
    flows: [
      .init(
        id: "quiz.open", title: "Open quiz", startRoute: "quiz",
        entryRoutes: ["onboarding"],
        steps: [
          .init(
            id: "assert", title: "Quiz is open", kind: .assert,
            predicate: .init(kind: .route, route: "quiz"))
        ],
        acceptance: [.init(kind: .route, route: "quiz")])
    ])

  let expanded = blueprint.expandingRecoverableFlowEntries()
  #expect(expanded.flows[0].entryRoutes == ["onboarding", "home", "quiz"])
  try expanded.validate()

  let url = FileManager.default.temporaryDirectory
    .appending(path: "lys-derived-entries-\(UUID().uuidString).json")
  try JSONEncoder().encode(blueprint).write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let loaded = try InteractionBlueprint.load(from: url)
  #expect(loaded.flows[0].entryRoutes == ["onboarding", "home", "quiz"])
}

@Test func semanticResolverKeepsAnOffscreenControlActionable() {
  let element = UIElement(
    type: "Button", identifier: "lys.action.home.open.quiz", label: "Quiz",
    visible: false, hittable: false,
    frame: .init(x: 20, y: 1_400, width: 300, height: 64), childPath: "0.1.9",
    xpath: "/Application/ScrollView/Button[4]", owningApplication: "com.example.app",
    availableActions: ["tap"], accessible: true)

  switch BlueprintControlResolver.resolve(
    .init(identifier: "lys.action.home.open.quiz"), in: [element])
  {
  case .offscreen(let resolved):
    #expect(resolved.identifier == "lys.action.home.open.quiz")
  default:
    Issue.record("Expected the semantic control to resolve as offscreen")
  }
}

@Test func revealPlannerChoosesThePageScrollViewAndCorrectDirection() throws {
  let page = UIElement(
    type: "ScrollView", visible: true, hittable: true,
    frame: .init(x: 0, y: 80, width: 390, height: 700), childPath: "0.1",
    owningApplication: "com.example.app", availableActions: ["scrollUp", "scrollDown"])
  let rail = UIElement(
    type: "ScrollView", visible: true, hittable: true,
    frame: .init(x: 20, y: 300, width: 350, height: 120), childPath: "0.1.3",
    owningApplication: "com.example.app", availableActions: ["scrollUp", "scrollDown"])
  let quiz = UIElement(
    type: "Button", identifier: "lys.action.home.open.quiz", visible: false,
    hittable: false, frame: .init(x: 20, y: 1_400, width: 350, height: 64),
    childPath: "0.1.9", owningApplication: "com.example.app", availableActions: ["tap"])

  let surface = try #require(
    BlueprintRevealPlanner.scrollSurface(in: [rail, page, quiz], action: "scrollUp"))
  #expect(surface.childPath == page.childPath)
  #expect(BlueprintRevealPlanner.preferredAction(for: quiz, scrollSurface: surface) == "scrollUp")
}

@Test func blueprintRejectsAnActionInvokedFromTheWrongRoute() {
  let contract = InteractionBlueprint(
    app: .init(entryRoutes: ["home"]),
    routes: [
      .init(
        id: "home", title: "Home",
        match: [.init(kind: .visible, selector: .init(identifier: "lys.screen.home"))]),
      .init(
        id: "quiz", title: "Quiz",
        match: [.init(kind: .visible, selector: .init(identifier: "lys.screen.quiz"))]),
    ],
    capabilities: [
      .init(
        id: "quiz.start", title: "Start", route: "quiz", action: .tap,
        selector: .init(identifier: "lys.action.quiz.start"))
    ],
    flows: [
      .init(
        id: "quiz.complete", title: "Complete quiz", startRoute: "home",
        entryRoutes: ["home"],
        steps: [.init(id: "start", title: "Start", kind: .invoke, capability: "quiz.start")],
        acceptance: [.init(kind: .route, route: "home")])
    ])

  #expect(throws: RPCError.self) { try contract.validate() }
}

@Test func blueprintRejectsAFlowThatListsOnlyItsOwnStartInsteadOfTheAppEntry() {
  let home = BlueprintRoute(
    id: "home", title: "Home",
    match: [.init(kind: .visible, selector: .init(identifier: "lys.screen.home"))])
  let quiz = BlueprintRoute(
    id: "quiz.setup", title: "Quiz",
    match: [.init(kind: .visible, selector: .init(identifier: "lys.screen.quiz.setup"))])
  let contract = InteractionBlueprint(
    app: .init(entryRoutes: [home.id]), routes: [home, quiz],
    flows: [
      .init(
        id: "quiz.complete", title: "Complete quiz", startRoute: quiz.id,
        entryRoutes: [quiz.id],
        steps: [
          .init(
            id: "ready", title: "Quiz is ready", kind: .assert,
            predicate: .init(kind: .route, route: quiz.id))
        ],
        acceptance: [.init(kind: .route, route: quiz.id)])
    ])

  #expect(throws: RPCError.self) { try contract.validate() }
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
    app: .init(entryRoutes: ["home"]),
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
        startRoute: "home", entryRoutes: ["home"],
        steps: [.init(id: "home", title: "Reach home", kind: .navigate, route: "home")],
        acceptance: [.init(kind: .route, route: "home")])
    ])

  #expect(throws: RPCError.self) { try contract.validate() }
}

@Test func naturalLanguageSelectsOneDeclaredFlowWithoutAModel() {
  let flows = [
    BlueprintFlow(
      id: "auth.login", title: "Test sign in", description: "Authenticate a user",
      startRoute: "auth.login", entryRoutes: ["auth.login"],
      steps: [], acceptance: []),
    BlueprintFlow(
      id: "quiz.complete", title: "Complete a quiz", description: "Answer every quiz question",
      startRoute: "quiz", entryRoutes: ["quiz"],
      steps: [], acceptance: []),
  ]

  #expect(LysFlowMatcher.match(goal: "test the quiz", in: flows)?.id == "quiz.complete")
  #expect(LysFlowMatcher.match(goal: "verify sign in authentication", in: flows)?.id == "auth.login")
  #expect(LysFlowMatcher.match(goal: "test the app", in: flows) == nil)
  #expect(
    LysFlowMatcher.match(
      goal: "test the numbers page",
      in: [
        BlueprintFlow(
          id: "quiz.complete", title: "Complete a quiz", startRoute: "quiz",
          entryRoutes: ["quiz"], steps: [], acceptance: [])
      ]) == nil)
}
