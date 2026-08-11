import Foundation
import Testing

@testable import IOSDevCore

@Test func checkedInBlueprintExampleLoadsAndCrossValidates() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let blueprint = try InteractionBlueprint.load(
    from: repository.appending(path: "Examples/operate-blueprint.json"))

  #expect(blueprint.schemaVersion == 1)
  #expect(blueprint.flows.map(\.id) == ["quiz.complete"])
  #expect(blueprint.contexts?.first?.requiredSecrets == ["test.email", "test.password"])
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
    path: "operate-blueprint-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  #expect(try InteractionBlueprintDiscovery.load(in: root) == nil)
  #expect(InteractionBlueprintDiscovery.relativePath == ".operate/blueprint.json")
}
