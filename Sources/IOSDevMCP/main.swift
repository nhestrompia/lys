import Foundation
import IOSDevCore

struct MCPTool: Codable {
  var name: String
  var description: String
  var inputSchema: JSONValue
}

@main
enum IOSDevMCPMain {
  static let tools: [MCPTool] = [
    tool("workspace.describe", "Describe the isolated task workspace"),
    tool(
      "build.run", "Build the selected iOS application", ["container", "scheme", "destination"]),
    tool("build.cancel", "Cancel the active build"),
    tool("test.list", "List tests"), tool("test.run", "Run selected tests"),
    tool("simulator.list", "List available simulators"),
    tool("simulator.boot", "Boot a simulator", ["udid"]),
    tool(
      "simulator.configure", "Configure appearance, orientation, locale, or status bar", ["udid"]),
    tool("devserver.start", "Start or reuse the Expo Metro development server"),
    tool("devserver.status", "Report whether the Expo Metro development server is ready"),
    tool("devserver.stop", "Stop the task-owned Expo Metro development server"),
    tool(
      "app.install_launch",
      "Install and launch the selected application; for Expo pass startDevServer=true",
      ["udid", "appPath", "bundleID"]),
    tool("app.terminate", "Terminate the application", ["udid", "bundleID"]),
    tool("app.reset_data", "Erase application data after explicit approval", ["udid", "bundleID"]),
    tool("ui.snapshot", "Capture a structured accessibility hierarchy"),
    tool("ui.find", "Find semantic UI elements", ["selector"]),
    tool("ui.perform", "Perform a semantic UI action", ["selector", "action"]),
    tool("ui.wait", "Wait for a semantic UI condition"),
    tool("ui.assert", "Assert a semantic UI condition", ["criterionID", "selector"]),
    tool("ui.navigate", "Replay deterministic observed App Graph edges", ["screen"]),
    tool("screenshot.capture", "Capture a simulator screenshot", ["udid"]),
    tool("logs.query", "Query bounded task runtime logs"),
    tool("verification.status", "Report host-validated evidence status"),
    tool("verification.submit", "Submit an evidence manifest for validation", ["evidenceIDs"]),
  ]

  static func main() {
    guard let socket = ProcessInfo.processInfo.environment["IOSDEVD_SOCKET"],
      let token = ProcessInfo.processInfo.environment["IOSDEVD_TASK_TOKEN"]
    else {
      FileHandle.standardError.write(
        Data("iosdev-mcp requires IOSDEVD_SOCKET and IOSDEVD_TASK_TOKEN\n".utf8))
      exit(64)
    }
    var framer = LineFramer()
    while true {
      let data = FileHandle.standardInput.availableData
      if data.isEmpty { return }
      for line in framer.append(data) {
        guard let request = try? JSONRPCCodec.decodeLine(line),
          let response = handle(request, socket: socket, token: token)
        else { continue }
        try? FileHandle.standardOutput.write(contentsOf: JSONRPCCodec.encodeLine(response))
      }
    }
  }

  private static func handle(_ request: RPCEnvelope, socket: String, token: String) -> RPCEnvelope?
  {
    switch request.method {
    case "initialize":
      return .init(
        id: request.id,
        result: .object([
          "protocolVersion": .string("2025-03-26"),
          "serverInfo": .object(["name": .string("iosdev-mcp"), "version": .string("0.1.0")]),
          "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
        ]))
    case "notifications/initialized": return nil
    case "tools/list":
      return .init(
        id: request.id, result: .object(["tools": (try? jsonValue(tools)) ?? .array([])]))
    case "tools/call":
      guard let toolName = request.params?["name"]?.stringValue else {
        return .init(id: request.id, error: .init(code: -32602, message: "Tool name is required"))
      }
      let arguments = request.params?["arguments"] ?? .object([:])
      do {
        let connection = try UnixSocketConnection.connect(path: socket)
        try connection.send(
          .init(
            id: .int(0), method: "runtime.authenticate", params: .object(["token": .string(token)]))
        )
        let authentication = try connection.receive()
        if let error = authentication.error { throw error }
        try connection.send(.init(id: request.id, method: toolName, params: arguments))
        let runtime = try connection.receive()
        if let error = runtime.error {
          return toolError(request.id, "\(error.message) [\(error.code)]")
        }
        let text =
          String(
            data: (try? JSONEncoder().encode(runtime.result ?? .null)) ?? Data(), encoding: .utf8)
          ?? "null"
        return .init(
          id: request.id,
          result: .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(false),
          ]))
      } catch { return toolError(request.id, error.localizedDescription) }
    default: return .init(id: request.id, error: .init(code: -32601, message: "Unknown MCP method"))
    }
  }

  private static func toolError(_ id: RPCID?, _ message: String) -> RPCEnvelope {
    .init(
      id: id,
      result: .object([
        "content": .array([.object(["type": .string("text"), "text": .string(message)])]),
        "isError": .bool(true),
      ]))
  }
  private static func tool(_ name: String, _ description: String, _ required: [String] = [])
    -> MCPTool
  {
    let properties = Dictionary(
      uniqueKeysWithValues: required.map { ($0, JSONValue.object(["type": .string("string")])) })
    return .init(
      name: name, description: description,
      inputSchema: .object([
        "type": .string("object"), "properties": .object(properties),
        "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(true),
      ]))
  }
}
