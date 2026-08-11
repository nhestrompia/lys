import Foundation
import Testing

@testable import IOSDevCore

private final class ACPUpdateRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var methods: [String] = []

  func append(_ envelope: RPCEnvelope) {
    lock.withLock { methods.append(envelope.method ?? "") }
  }

  var snapshot: [String] { lock.withLock { methods } }
}

@Test func jsonRPCRoundTripAndFraming() throws {
  let message = RPCEnvelope(
    id: .int(42), method: "build.run", params: .object(["scheme": .string("Demo")]))
  let encoded = try JSONRPCCodec.encodeLine(message)
  let decoded = try JSONRPCCodec.decodeLine(encoded)
  #expect(decoded.jsonrpc == "2.0")
  #expect(decoded.id == .int(42))
  #expect(decoded.params?["scheme"] == .string("Demo"))
  var framer = LineFramer()
  #expect(framer.append(encoded.prefix(4)).isEmpty)
  #expect(framer.append(encoded.dropFirst(4)).count == 1)
}

@Test func acpPathPolicyRejectsTraversal() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let policy = ACPPathPolicy(workspace: root)
  #expect(throws: Never.self) { try policy.resolve("Sources/App.swift") }
  #expect(throws: (any Error).self) { try policy.resolve("../secrets") }
  #expect(throws: (any Error).self) { try policy.resolve("/etc/passwd") }
}

@Test func acpInitializeUsesOfficialV1CapabilityShape() throws {
  let value = try jsonValue(ACPInitialize(clientVersion: "0.1.0", allowWrites: true))
  #expect(value["protocolVersion"] == .number(1))
  #expect(value["clientInfo"]?["name"] == .string("lys"))
  #expect(value["clientCapabilities"]?["terminal"] == .bool(false))
  #expect(value["clientCapabilities"]?["fs"]?["readTextFile"] == .bool(true))
  #expect(value["clientCapabilities"]?["fs"]?["writeTextFile"] == .bool(true))
}

@Test func acpStdioMCPEnvironmentUsesOfficialNameValueArray() throws {
  let value = try jsonValue(
    ACPMCPServer(
      name: "Lys Runtime", command: "/absolute/lys-mcp",
      env: ["LYS_TASK_TOKEN": "token", "LYS_RUNTIME_SOCKET": "/tmp/runtime.sock"]))
  #expect(value["command"] == .string("/absolute/lys-mcp"))
  #expect(
    value["env"] == .array([
      .object(["name": .string("LYS_RUNTIME_SOCKET"), "value": .string("/tmp/runtime.sock")]),
      .object(["name": .string("LYS_TASK_TOKEN"), "value": .string("token")]),
    ]))
}

@Test func acpSessionConfigOptionsExposeModelAndReasoningValues() throws {
  let payload: JSONValue = .array([
    .object([
      "id": .string("model"), "name": .string("Model"), "category": .string("model"),
      "type": .string("select"), "currentValue": .string("model-a"),
      "options": .array([
        .object(["value": .string("model-a"), "name": .string("Model A")]),
        .object(["value": .string("model-b"), "name": .string("Model B")]),
      ]),
    ]),
    .object([
      "id": .string("reasoning_effort"), "name": .string("Reasoning effort"),
      "category": .string("thought_level"), "type": .string("select"),
      "currentValue": .string("high"),
      "options": .array([
        .object(["value": .string("low"), "name": .string("Low")]),
        .object(["value": .string("high"), "name": .string("High")]),
      ]),
    ]),
  ])
  let data = try JSONEncoder().encode(payload)
  let options = try JSONDecoder().decode([ACPConfigOption].self, from: data)
  #expect(options.count == 2)
  #expect(options.first?.category == "model")
  #expect(options.first?.currentValue == .string("model-a"))
  #expect(options.last?.options.last?.name == "High")
}

@Test func acpWorkspaceRequestsStayInsideWorktreeAndTrackMutations() async throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let handler = ACPWorkspaceRequestHandler(workspace: root, allowWrites: true)
  let written = await handler.handle(
    .init(
      id: .int(1), method: "fs/write_text_file",
      params: .object(["path": .string("Sources/App.swift"), "content": .string("let app = 1")]))
  )
  #expect(written.error == nil)
  let read = await handler.handle(
    .init(
      id: .int(2), method: "fs/read_text_file",
      params: .object(["path": .string("Sources/App.swift")]))
  )
  #expect(read.result?["content"] == .string("let app = 1"))
  let escaped = await handler.handle(
    .init(
      id: .int(3), method: "fs/read_text_file",
      params: .object(["path": .string("../secret")]))
  )
  #expect(escaped.error?.code == -32060)
}

@Test func configurationRejectsUnknownSchema() throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  try Data(#"{"schemaVersion":2,"scheme":"Demo"}"#.utf8).write(to: url)
  #expect(throws: (any Error).self) { try LysConfiguration.load(from: url) }
}

@Test func modelAgnosticACPAdapterCompletesAFullSessionOverStdio() async throws {
  let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
  let script = try #require(
    Bundle.module.url(forResource: "fake_acp", withExtension: "py", subdirectory: "Fixtures"))
  let updates = ACPUpdateRecorder()
  let client = try ACPClient(
    executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [script.path],
    workspace: workspace,
    onUpdate: { updates.append($0) })

  let initialized = try await client.request(
    method: "initialize", params: try jsonValue(ACPInitialize(clientVersion: "test", allowWrites: false)))
  #expect(initialized.result?["protocolVersion"] == .number(1))

  let session = try await client.request(
    method: "session/new", params: .object(["cwd": .string(workspace.path)]))
  #expect(session.result?["sessionId"] == .string("fake-session"))

  let prompt = try await client.request(
    method: "session/prompt",
    params: .object([
      "sessionId": .string("fake-session"),
      "prompt": .array([
        .object(["type": .string("text"), "text": .string("Test the quiz")])
      ]),
    ]))
  #expect(prompt.result?["stopReason"] == .string("end_turn"))
  #expect(updates.snapshot.contains("session/update"))
  client.cancel()
}
