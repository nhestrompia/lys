import Foundation

public struct AgentRuntimeToolDefinition: Codable, Sendable {
  public var name: String
  public var description: String
  public var inputSchema: JSONValue
  public var outputSchema: JSONValue?
  public var annotations: JSONValue?

  public init(
    name: String, description: String, inputSchema: JSONValue,
    outputSchema: JSONValue? = nil, annotations: JSONValue? = nil
  ) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
    self.outputSchema = outputSchema
    self.annotations = annotations
  }
}

public enum AgentRuntimeToolCatalog {
  public static func allows(_ name: String, for kind: AgentTaskKind?) -> Bool {
    definition(named: name, for: kind) != nil
  }

  public static func definition(
    named name: String, for kind: AgentTaskKind?
  ) -> AgentRuntimeToolDefinition? {
    tools(for: kind).first { $0.name == name }
  }

  public static func argumentViolation(
    for tool: AgentRuntimeToolDefinition, arguments: JSONValue
  ) -> String? {
    validate(arguments, against: tool.inputSchema, path: "arguments")
  }

  public static func tools(for kind: AgentTaskKind?) -> [AgentRuntimeToolDefinition] {
    let common = [
      tool(
        "workspace.describe",
        "Inspect the host-selected workspace and testing policy. Call this instead of searching for Xcode project metadata.",
        properties: [:], readOnly: true),
      tool(
        "app.describe",
        "Read the current logical screen and executable capabilities. Lys merges its repository test contract with the live accessibility state.",
        properties: [:], readOnly: true,
        output: object(
          [
            "contract": boolean("Whether a Lys test contract was loaded"),
            "currentRoute": nullableString("Current stable route ID when known"),
            "routes": array(items: openObject()),
            "capabilities": array(items: openObject()),
            "progress": openValue(), "stateVersion": openValue(),
            "message": string("Short host explanation"),
          ], required: ["contract", "routes", "capabilities", "message"])),
      tool(
        "flow.list",
        "List flows declared by the Lys SDK contract. An empty list means only exploratory testing is available.",
        properties: [:], readOnly: true,
        output: object(
          [
            "flows": array(items: openObject()),
            "contractAvailable": boolean("Whether a Lys contract exists"),
            "message": string("Short host explanation"),
          ], required: ["flows", "contractAvailable", "message"])),
      tool(
        "flow.run",
        "Run one complete host-owned Lys flow, including authenticated-session setup, bounded loops, every acceptance criterion, evidence, and terminal completion. Omit flowID only for explicitly exploratory testing.",
        properties: [
          "goal": string("Natural-language outcome to test"),
          "flowID": string("Optional exact ID returned by flow.list"),
          "parameters": openObject(),
        ], required: ["goal"], readOnly: false, destructive: false, idempotent: false,
        output: openObject()),
      tool(
        "flow.step",
        "Continue an exploratory flow with one exact capability from the latest app state. Declared Lys flows never need this tool.",
        properties: [
          "flowID": string("Active flow ID"),
          "stepID": string("Stable step name for evidence"),
          "title": string("Short user-visible action title"),
          "capabilityID": string("Exact capability ID returned by app.describe or flow.run"),
          "action": string(
            "Advertised primitive action",
            allowed: ["tap", "type", "clear", "scrollUp", "scrollDown"]),
          "text": string("Text for type actions"),
          "expectScreenChanged": boolean("Require a logical screen change"),
        ], required: ["flowID", "capabilityID", "action"], readOnly: false,
        destructive: false, idempotent: false, output: openObject()),
      tool(
        "flow.finish",
        "Ask the host to validate terminal state, evidence, and acceptance criteria for a zero-integration flow.",
        properties: ["flowID": string("Active flow ID")], required: ["flowID"],
        readOnly: false, destructive: false, idempotent: true, output: openObject()),
      tool(
        "flow.status", "Read the active flow and its host-recorded step results.",
        properties: ["flowID": string("Flow ID; omit for the active flow")], readOnly: true,
        output: openObject()),
      tool(
        "flow.stop",
        "Stop only the active flow. The app, Simulator, and development server remain running.",
        properties: ["flowID": string("Flow ID; omit for the active flow")],
        readOnly: false, destructive: false, idempotent: true,
        output: object(
          [
            "cancelled": boolean("Whether an active flow was cancelled"),
            "message": string("Preservation status"),
          ], required: ["cancelled", "message"])),
      tool(
        "screenshot.capture",
        "Capture stable current Simulator evidence using host-selected context.",
        properties: [:], readOnly: true),
      tool(
        "logs.query", "Query bounded logs for the host-selected app.",
        properties: ["seconds": number("Lookback seconds, from 1 to 3600")], readOnly: true),
      tool(
        "evidence.summary",
        "Return the host-owned final status: what ran, what passed, and what remains missing.",
        properties: [:], readOnly: true,
        output: object(
          [
            "status": string("Verification status"), "flowStatus": string("Flow status"),
            "missing": array(items: string("Missing host criterion")),
            "evidenceCount": number("Fresh evidence item count"),
            "message": string("Short understandable summary"),
          ], required: ["status", "flowStatus", "missing", "evidenceCount", "message"])),
    ]
    switch kind {
    case .runTests:
      return [common[0], testListTool, testRunTool]
        + common.filter { $0.name == "evidence.summary" }
    case .modifyAndVerify:
      return common + [buildTool, testListTool, testRunTool]
    case .verifyCurrentApp, .inspectCurrentApp, nil:
      return common
    }
  }

  private static let buildTool = tool(
    "build.run",
    "Build only when the host-selected mutation generation requires it. Project, scheme, destination, cache, and target discovery are automatic.",
    properties: [:], readOnly: false, destructive: false, idempotent: true)
  private static let testListTool = tool(
    "test.list", "List test plans for the host-selected project and scheme.", properties: [:],
    readOnly: true)
  private static let testRunTool = tool(
    "test.run", "Run tests for the host-selected project, scheme, and destination.",
    properties: ["onlyTesting": array(items: string("Optional test identifier"))],
    readOnly: true)

  private static func tool(
    _ name: String, _ description: String, properties: [String: JSONValue],
    required: [String] = [], readOnly: Bool, destructive: Bool = false,
    idempotent: Bool = false, output: JSONValue? = nil
  ) -> AgentRuntimeToolDefinition {
    .init(
      name: name, description: description,
      inputSchema: .object([
        "type": .string("object"), "properties": .object(properties),
        "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false),
      ]),
      outputSchema: output ?? openObject(),
      annotations: .object([
        "title": .string(name), "readOnlyHint": .bool(readOnly),
        "destructiveHint": .bool(destructive), "idempotentHint": .bool(idempotent),
        "openWorldHint": .bool(false),
      ]))
  }

  private static func string(_ description: String, allowed: [String]? = nil) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": .string("string"), "description": .string(description),
    ]
    if let allowed { schema["enum"] = .array(allowed.map(JSONValue.string)) }
    return .object(schema)
  }
  private static func boolean(_ description: String) -> JSONValue {
    .object(["type": .string("boolean"), "description": .string(description)])
  }
  private static func number(_ description: String) -> JSONValue {
    .object(["type": .string("number"), "description": .string(description)])
  }
  private static func array(items: JSONValue) -> JSONValue {
    .object(["type": .string("array"), "items": items])
  }
  private static func object(
    _ properties: [String: JSONValue], required: [String] = []
  ) -> JSONValue {
    .object([
      "type": .string("object"), "properties": .object(properties),
      "required": .array(required.map(JSONValue.string)),
      "additionalProperties": .bool(false),
    ])
  }
  private static func nullableString(_ description: String) -> JSONValue {
    .object([
      "anyOf": .array([
        .object(["type": .string("string")]),
        .object(["type": .string("null")]),
      ]),
      "description": .string(description),
    ])
  }
  private static func openObject() -> JSONValue {
    .object(["type": .string("object"), "additionalProperties": .bool(true)])
  }
  private static func openValue() -> JSONValue { .object([:]) }

  private static func validate(
    _ value: JSONValue, against schema: JSONValue, path: String
  ) -> String? {
    switch schema["type"]?.stringValue {
    case "object":
      guard case .object(let values) = value else { return "\(path) must be an object" }
      let properties: [String: JSONValue]
      if case .object(let declared)? = schema["properties"] {
        properties = declared
      } else {
        properties = [:]
      }
      if schema["additionalProperties"]?.boolValue == false,
        let unexpected = values.keys.sorted().first(where: { properties[$0] == nil })
      {
        return "\(path).\(unexpected) is not accepted by the host contract"
      }
      for required in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
      where values[required] == nil {
        return "\(path).\(required) is required"
      }
      for (key, child) in values {
        if let childSchema = properties[key],
          let violation = validate(child, against: childSchema, path: "\(path).\(key)")
        {
          return violation
        }
      }
    case "array":
      guard case .array(let values) = value else { return "\(path) must be an array" }
      if let itemSchema = schema["items"] {
        for (index, child) in values.enumerated() {
          if let violation = validate(child, against: itemSchema, path: "\(path)[\(index)]") {
            return violation
          }
        }
      }
    case "string":
      guard case .string(let stringValue) = value else { return "\(path) must be a string" }
      let allowed = schema["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
      if !allowed.isEmpty, !allowed.contains(stringValue) {
        return "\(path) must be one of: \(allowed.joined(separator: ", "))"
      }
    case "boolean":
      guard case .bool = value else { return "\(path) must be a boolean" }
    case "number":
      guard case .number = value else { return "\(path) must be a number" }
    default: break
    }
    return nil
  }
}
