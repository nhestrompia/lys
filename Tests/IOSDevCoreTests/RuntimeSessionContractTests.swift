import Foundation
import Testing

@testable import IOSDevCore

private func temporaryRuntimeRoot() throws -> URL {
  let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "iosdev-runtime-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
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
      id: .int(2), method: "journey.run",
      params: .object(["goal": .string("Validate the quiz scoring contract")])),
    authenticated: &authenticated)
  #expect(started.error == nil)
  #expect(started.result?["goal"] == .string("Validate the quiz scoring contract"))
  let firstID = started.result?["id"]?.stringValue

  let cancelled = await service.handle(
    .init(id: .int(3), method: "journey.cancel"), authenticated: &authenticated)
  #expect(cancelled.result?["cancelled"] == .bool(true))
  #expect(cancelled.result?["message"]?.stringValue?.contains("preserved") == true)

  let status = await service.handle(
    .init(id: .int(4), method: "session.status"), authenticated: &authenticated)
  #expect(status.result?["configured"] == .bool(true))
  #expect(status.result?["journey"]?["status"] == .string("cancelled"))

  let restarted = await service.handle(
    .init(
      id: .int(5), method: "journey.run",
      params: .object(["goal": .string("Validate quiz accessibility")])),
    authenticated: &authenticated)
  #expect(restarted.result?["goal"] == .string("Validate quiz accessibility"))
  #expect(restarted.result?["id"]?.stringValue != firstID)
}
