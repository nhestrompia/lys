import Foundation
import IOSDevCore

@main
enum IOSDevMCPMain {
  static var tools: [AgentRuntimeToolDefinition] {
    let raw = ProcessInfo.processInfo.environment["IOSDEV_INTENT_KIND"]
    return AgentRuntimeToolCatalog.tools(for: raw.flatMap(AgentTaskKind.init(rawValue:)))
  }

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
      let rawIntent = ProcessInfo.processInfo.environment["IOSDEV_INTENT_KIND"]
      let intent = rawIntent.flatMap(AgentTaskKind.init(rawValue:))
      guard let tool = AgentRuntimeToolCatalog.definition(named: toolName, for: intent) else {
        return toolError(
          request.id,
          "The host policy does not allow \(toolName) for this testing intent.")
      }
      let arguments = request.params?["arguments"] ?? .object([:])
      if let violation = AgentRuntimeToolCatalog.argumentViolation(
        for: tool, arguments: arguments)
      {
        return toolError(request.id, violation)
      }
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
        let structured = runtime.result ?? .object([:])
        let text = humanSummary(tool: toolName, result: structured)
        return .init(
          id: request.id,
          result: .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "structuredContent": structured,
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
  private static func humanSummary(tool: String, result: JSONValue) -> String {
    if let message = result["message"]?.stringValue { return message }
    if let detail = result["detail"]?.stringValue { return detail }
    if let status = result["status"]?.stringValue {
      return "\(tool) completed with status \(status)."
    }
    if result["succeeded"]?.boolValue == true { return "\(tool) completed successfully." }
    if result["passed"]?.boolValue == true { return "\(tool) passed." }
    return "\(tool) completed. Structured results are attached."
  }
}
