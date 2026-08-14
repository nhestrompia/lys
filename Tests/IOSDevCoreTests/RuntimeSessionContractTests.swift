import Foundation
import Testing

@testable import IOSDevCore

private func temporaryRuntimeRoot() throws -> URL {
  let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "lys-runtime-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

@Test func oldContractSchemaFailsClearlyAndDoesNotPartiallyConfigureTheSession() async throws {
  let root = try temporaryRuntimeRoot()
  let contractURL = root.appending(path: ".lys/contract.json")
  try FileManager.default.createDirectory(
    at: contractURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data(
    #"{"schemaVersion":1,"flows":[{"id":"quiz.complete","title":"Quiz","steps":[],"acceptance":[]}]}"#
      .utf8
  ).write(to: contractURL)

  let service = RuntimeService(workspace: root, token: "secret", stateRoot: root)
  var authenticated = true
  let configuration = RuntimeSessionConfiguration(
    intent: AgentTaskIntentRouter.classify("Test the quiz"), container: nil,
    scheme: "Demo", destination: nil, target: nil, startDevelopmentServer: false)
  let configured = await service.handle(
    .init(id: .int(1), method: "session.configure", params: try jsonValue(configuration)),
    authenticated: &authenticated)

  #expect(configured.error?.code == -32110)
  #expect(configured.error?.message.contains("Regenerate .lys/contract.json") == true)
  let status = await service.handle(
    .init(id: .int(2), method: "session.status"), authenticated: &authenticated)
  #expect(status.result?["configured"] == .bool(false))
}

@Test func unmatchedGoalUsesExplorationAlongsidePartialContract() async throws {
  let root = try temporaryRuntimeRoot()
  let contractURL = root.appending(path: ".lys/contract.json")
  try FileManager.default.createDirectory(
    at: contractURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  let noCrash = BlueprintPredicate(kind: .noCrash)
  let contract = InteractionBlueprint(
    app: .init(entryRoutes: ["quiz"]),
    routes: [
      .init(
        id: "quiz", title: "Quiz",
        match: [.init(kind: .visible, selector: .init(identifier: "lys.screen.quiz"))])
    ],
    flows: [
      .init(
        id: "quiz.complete", title: "Complete quiz", startRoute: "quiz",
        entryRoutes: ["quiz"],
        steps: [
          .init(id: "noCrash", title: "App remains healthy", kind: .assert, predicate: noCrash)
        ], acceptance: [noCrash])
    ])
  try JSONEncoder().encode(contract).write(to: contractURL)

  let service = RuntimeService(workspace: root, token: "secret", stateRoot: root)
  var authenticated = true
  let configuration = RuntimeSessionConfiguration(
    intent: AgentTaskIntentRouter.classify("Run the unit test suite"), container: nil,
    scheme: "Demo", destination: nil, target: nil, startDevelopmentServer: false)
  _ = await service.handle(
    .init(id: .int(1), method: "session.configure", params: try jsonValue(configuration)),
    authenticated: &authenticated)

  let result = await service.handle(
    .init(
      id: .int(2), method: "flow.run",
      params: .object(["goal": .string("Test the numbers page")])),
    authenticated: &authenticated)

  #expect(result.error == nil)
  #expect(result.result?["goal"] == .string("Test the numbers page"))
  #expect(result.result?["mode"] == .string("exploratory"))
}

@Test func flowListExposesTheDefaultHostIsolationPolicy() async throws {
  let root = try temporaryRuntimeRoot()
  let contractURL = root.appending(path: ".lys/contract.json")
  try FileManager.default.createDirectory(
    at: contractURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  let home = BlueprintRoute(
    id: "home", title: "Home",
    match: [.init(kind: .visible, selector: .init(identifier: "lys.screen.home"))])
  let results = BlueprintRoute(
    id: "results", title: "Results",
    match: [.init(kind: .visible, selector: .init(identifier: "lys.screen.results"))], terminal: true)
  let contract = InteractionBlueprint(
    app: .init(entryRoutes: [home.id]), routes: [home, results],
    capabilities: [
      .init(
        id: "home.results", title: "Open results", route: home.id, resultsIn: results.id,
        action: .tap, selector: .init(identifier: "lys.action.home.results"))
    ],
    contexts: [
      .init(id: "independent", title: "Independent", readyWhen: [.init(kind: .route, route: home.id)])
    ],
    flows: [
      .init(
        id: "results.check", title: "Check results", context: "independent",
        startRoute: home.id, entryRoutes: [home.id],
        steps: [.init(id: "open", title: "Open results", kind: .invoke, capability: "home.results")],
        acceptance: [.init(kind: .route, route: results.id)])
    ])
  try JSONEncoder().encode(contract).write(to: contractURL)

  let service = RuntimeService(workspace: root, token: "secret", stateRoot: root)
  var authenticated = true
  let configuration = RuntimeSessionConfiguration(
    intent: AgentTaskIntentRouter.classify("Test the results"), container: nil,
    scheme: "Demo", destination: nil, target: nil, startDevelopmentServer: false)
  _ = await service.handle(
    .init(id: .int(1), method: "session.configure", params: try jsonValue(configuration)),
    authenticated: &authenticated)
  let listed = await service.handle(
    .init(id: .int(2), method: "flow.list"), authenticated: &authenticated)

  #expect(listed.result?["flows"]?.arrayValue?.first?["isolation"] == .string("relaunch"))
}

@Test func newExploratoryRunReplacesAnUnfinishedJourney() async throws {
  let root = try temporaryRuntimeRoot()
  let service = RuntimeService(workspace: root, token: "secret", stateRoot: root)
  var authenticated = true
  let configuration = RuntimeSessionConfiguration(
    intent: AgentTaskIntentRouter.classify("Run the unit test suite"), container: nil,
    scheme: "Demo", destination: nil, target: nil, startDevelopmentServer: false)
  _ = await service.handle(
    .init(id: .int(1), method: "session.configure", params: try jsonValue(configuration)),
    authenticated: &authenticated)

  let first = await service.handle(
    .init(
      id: .int(2), method: "flow.run",
      params: .object(["goal": .string("Explore the first feature")])),
    authenticated: &authenticated)
  let second = await service.handle(
    .init(
      id: .int(3), method: "flow.run",
      params: .object(["goal": .string("Explore the second feature")])),
    authenticated: &authenticated)

  #expect(first.error == nil)
  #expect(second.error == nil)
  #expect(first.result?["id"] != second.result?["id"])
  #expect(second.result?["goal"] == .string("Explore the second feature"))
  let staleStatus = await service.handle(
    .init(
      id: .int(4), method: "flow.status",
      params: .object(["journeyID": first.result?["id"] ?? .null])),
    authenticated: &authenticated)
  #expect(staleStatus.error?.code == -32084)
}

@Test func runtimeSessionEnforcesHostIntentAndPublishesEvents() async throws {
  let root = try temporaryRuntimeRoot()
  let service = RuntimeService(workspace: root, token: "secret", stateRoot: root)
  var authenticated = false

  let rejected = await service.handle(
    .init(id: .int(1), method: "workspace.describe"), authenticated: &authenticated)
  #expect(rejected.error?.code == -32000)

  let authentication = await service.handle(
    .init(
      id: .int(2), method: "runtime.authenticate",
      params: .object(["token": .string("secret")])),
    authenticated: &authenticated)
  #expect(authentication.error == nil)
  #expect(authenticated)

  let intent = AgentTaskIntentRouter.classify("Run the unit test suite")
  let configuration = RuntimeSessionConfiguration(
    intent: intent, container: nil, scheme: "Quiz", destination: nil, target: nil,
    startDevelopmentServer: false)
  let configured = await service.handle(
    .init(id: .int(3), method: "session.configure", params: try jsonValue(configuration)),
    authenticated: &authenticated)
  #expect(configured.result?["configured"] == .bool(true))

  let workspace = await service.handle(
    .init(id: .int(4), method: "workspace.describe"), authenticated: &authenticated)
  #expect(workspace.result?["root"] == .string(root.path))
  #expect(workspace.result?["writable"] == .bool(false))
  #expect(workspace.result?["intent"]?["kind"] == .string("runTests"))

  let events = await service.handle(
    .init(
      id: .int(5), method: "runtime.events",
      params: .object(["after": .number(0)])),
    authenticated: &authenticated)
  #expect(events.result?["latestSequence"] == .number(1))
  #expect(events.result?["events"]?.arrayValue?.first?["kind"] == .string("sessionConfigured"))
}

@Test func cancellingJourneyPreservesRuntimeOwnership() async throws {
  let root = try temporaryRuntimeRoot()
  let service = RuntimeService(workspace: root, token: "secret", stateRoot: root)
  var authenticated = true
  let intent = AgentTaskIntentRouter.classify("Run the unit test suite")
  let configuration = RuntimeSessionConfiguration(
    intent: intent, container: nil, scheme: "Quiz", destination: nil, target: nil,
    startDevelopmentServer: false)
  _ = await service.handle(
    .init(id: .int(1), method: "session.configure", params: try jsonValue(configuration)),
    authenticated: &authenticated)
  let started = await service.handle(
    .init(
      id: .int(2), method: "flow.run",
      params: .object(["goal": .string("Validate the quiz scoring contract")])),
    authenticated: &authenticated)
  #expect(started.error == nil)
  #expect(started.result?["goal"] == .string("Validate the quiz scoring contract"))
  let firstID = started.result?["id"]?.stringValue

  let cancelled = await service.handle(
    .init(id: .int(3), method: "flow.stop"), authenticated: &authenticated)
  #expect(cancelled.result?["cancelled"] == .bool(true))
  #expect(cancelled.result?["message"]?.stringValue?.contains("preserved") == true)

  let status = await service.handle(
    .init(id: .int(4), method: "session.status"), authenticated: &authenticated)
  #expect(status.result?["configured"] == .bool(true))
  #expect(status.result?["journey"]?["status"] == .string("cancelled"))

  let restarted = await service.handle(
    .init(
      id: .int(5), method: "flow.run",
      params: .object(["goal": .string("Validate quiz accessibility")])),
    authenticated: &authenticated)
  #expect(restarted.result?["goal"] == .string("Validate quiz accessibility"))
  #expect(restarted.result?["id"]?.stringValue != firstID)
}

@Test func hostStopBlocksAgentActionsUntilTheUserResumes() async throws {
  let root = try temporaryRuntimeRoot()
  let service = RuntimeService(workspace: root, token: "secret", stateRoot: root)
  var authenticated = true
  let configuration = RuntimeSessionConfiguration(
    intent: AgentTaskIntentRouter.classify("Run the unit test suite"), container: nil,
    scheme: "Quiz", destination: nil, target: nil, startDevelopmentServer: false)
  _ = await service.handle(
    .init(id: .int(1), method: "session.configure", params: try jsonValue(configuration)),
    authenticated: &authenticated)
  _ = await service.handle(
    .init(
      id: .int(2), method: "flow.run",
      params: .object(["goal": .string("Validate the quiz")])),
    authenticated: &authenticated)

  let stopped = await service.handle(
    .init(id: .int(3), method: "session.stop"), authenticated: &authenticated)
  #expect(stopped.result?["stopped"] == .bool(true))
  let rejected = await service.handle(
    .init(
      id: .int(4), method: "flow.run",
      params: .object(["goal": .string("Keep acting without the user")])),
    authenticated: &authenticated)
  #expect(rejected.error?.code == -32097)

  _ = await service.handle(
    .init(id: .int(5), method: "session.resume"), authenticated: &authenticated)
  let resumed = await service.handle(
    .init(
      id: .int(6), method: "flow.run",
      params: .object(["goal": .string("Continue after the user asks")])),
    authenticated: &authenticated)
  #expect(resumed.error == nil)
}

@Test func runtimeAcceptsSparseAgentJourneyStepsWithoutDecoderFailure() async throws {
  let root = try temporaryRuntimeRoot()
  let service = RuntimeService(workspace: root, token: "secret", stateRoot: root)
  var authenticated = true
  let configuration = RuntimeSessionConfiguration(
    intent: AgentTaskIntentRouter.classify("Run the unit test suite"), container: nil,
    scheme: "Quiz", destination: nil, target: nil, startDevelopmentServer: false)
  _ = await service.handle(
    .init(id: .int(1), method: "session.configure", params: try jsonValue(configuration)),
    authenticated: &authenticated)
  let started = await service.handle(
    .init(
      id: .int(2), method: "flow.run",
      params: .object(["goal": .string("Verify quiz entry")])),
    authenticated: &authenticated)
  let journeyID = try #require(started.result?["id"]?.stringValue)

  let continued = await service.handle(
    .init(
      id: .int(3), method: "flow.step",
      params: .object([
        "flowID": .string(journeyID), "stepID": .string("open-quiz"),
        "title": .string("Open quiz"), "capabilityID": .string("screen-action"),
        "action": .string("tap"), "expectScreenChanged": .bool(true),
      ])),
    authenticated: &authenticated)

  #expect(continued.error == nil)
  #expect(continued.result?["recoverable"] == .bool(true))
  #expect(continued.result?["steps"]?.arrayValue?.first?["step"]?["assertVisible"] == .bool(false))
}
