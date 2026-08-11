import Foundation
import Testing

@testable import IOSDevCore

@Test func sqliteStorePersistsEventsAndEvidence() async throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let store = try SQLiteStore(url: root.appending(path: "metadata.sqlite3"))
  let taskID = UUID()
  let event = StoredEvent(
    taskID: taskID, kind: "build.started", payload: .object(["scheme": .string("Demo")]))
  try await store.append(event)
  let item = Evidence(
    kind: .build, status: .passed, taskGeneration: 2, diagnosticSummary: "Fresh build")
  try await store.saveEvidence(item, taskID: taskID)
  #expect(try await store.events(taskID: taskID).map(\.id) == [event.id])
  #expect(try await store.evidence(taskID: taskID).map(\.id) == [item.id])
}

@Test func sqliteStorePersistsAppGraphSnapshots() async throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let store = try SQLiteStore(url: root.appending(path: "metadata.sqlite3"))
  let fingerprint = ScreenFingerprint(digest: "home", owningApplication: "com.example.app")
  let snapshot = AppGraphSnapshot(nodes: [.init(fingerprint: fingerprint, name: "Home")])
  try await store.saveAppGraph(snapshot, key: "com.example.app|Debug")
  let loaded = try await store.appGraph(key: "com.example.app|Debug")
  #expect(loaded?.nodes.map(\.id) == ["home"])
}
