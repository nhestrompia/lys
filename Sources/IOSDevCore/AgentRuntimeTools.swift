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
        "journey.run",
        "Start or continue a host-owned app-testing journey. The host reuses the running app when compatible, builds only when policy requires it, executes supplied semantic steps, records the App Graph, and returns current UI elements and evidence. Call first with only goal; then continue with journeyID and deterministic steps.",
        properties: [
          "goal": string("Natural-language user outcome to verify"),
          "journeyID": string("ID returned by an earlier journey.run call"),
          "complete": boolean("Finish the journey after these steps and capture final evidence"),
          "steps": array(
            items: object([
              "id": string("Stable step ID"), "title": string("Short user-visible step title"),
              "criterionID": string("Acceptance criterion ID"),
              "selector": object([
                "identifier": string("Accessibility identifier"),
                "label": string("Unique accessibility label"),
                "type": string("Accessibility element type when selecting by label"),
              ]),
              "action": string("tap, type, clear, or other WDA semantic action"),
              "text": string("Text for a type action"),
              "assertVisible": boolean("Assert the selector is uniquely visible after the action"),
            ]))
        ], required: ["goal"], readOnly: false, destructive: false, idempotent: false),
      tool(
        "journey.status", "Read the current testing journey and its step results.",
        properties: ["journeyID": string("Journey ID; omit for the active journey")],
        readOnly: true),
      tool(
        "journey.cancel", "Cancel only the active testing journey. This does not stop the app, Simulator, or development server.",
        properties: ["journeyID": string("Journey ID; omit for the active journey")],
        readOnly: false, destructive: false, idempotent: true),
      tool(
        "ui.snapshot", "Inspect the current app's semantic accessibility hierarchy. Simulator and bundle context are supplied by the host.",
        properties: [:], readOnly: true),
      tool(
        "ui.find", "Find semantic UI elements in the current app using an accessibility identifier or unique label and type.",
        properties: ["selector": selectorSchema], required: ["selector"], readOnly: true),
      tool(
        "ui.perform", "Perform one semantic action in the current app. The host records before/after states and makes the action visible in the App panel.",
        properties: [
          "selector": selectorSchema, "action": string("tap, type, clear, or swipe"),
          "text": string("Text for type actions"),
        ], required: ["selector", "action"], readOnly: false, destructive: false),
      tool(
        "ui.wait", "Wait with bounded automatic retry for a semantic UI selector.",
        properties: [
          "selector": selectorSchema, "timeoutSeconds": number("Timeout from 0.2 to 30 seconds"),
        ], required: ["selector"], readOnly: true),
      tool(
        "ui.assert", "Record deterministic evidence that one semantic UI element is visible.",
        properties: [
          "criterionID": string("Acceptance criterion ID"), "selector": selectorSchema,
        ], required: ["criterionID", "selector"], readOnly: true),
      tool(
        "ui.navigate", "Replay a previously observed deterministic App Graph path to a screen fingerprint.",
        properties: ["screen": string("Destination screen fingerprint")], required: ["screen"],
        readOnly: false, destructive: false),
      tool(
        "screenshot.capture", "Capture stable current Simulator evidence using host-selected context.",
        properties: [:], readOnly: true),
      tool(
        "logs.query", "Query bounded logs for the host-selected app.",
        properties: ["seconds": number("Lookback seconds, from 1 to 3600")], readOnly: true),
      tool(
        "verification.status", "Read host-validated evidence completeness for the active generation.",
        properties: [:], readOnly: true),
      tool(
        "verification.submit", "Submit current evidence IDs for host validation.",
        properties: ["evidenceIDs": array(items: string("Evidence UUID"))],
        required: ["evidenceIDs"], readOnly: true),
    ]
    switch kind {
    case .runTests:
      return [common[0], testListTool, testRunTool, common[12], common[13]]
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

  private static var selectorSchema: JSONValue {
    object([
      "identifier": string("Accessibility identifier"),
      "label": string("Unique accessibility label"),
      "type": string("Accessibility element type required with label"),
    ])
  }

  private static func tool(
    _ name: String, _ description: String, properties: [String: JSONValue],
    required: [String] = [], readOnly: Bool, destructive: Bool = false,
    idempotent: Bool = false
  ) -> AgentRuntimeToolDefinition {
    .init(
      name: name, description: description,
      inputSchema: .object([
        "type": .string("object"), "properties": .object(properties),
        "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false),
      ]),
      outputSchema: .object([
        "type": .string("object"), "additionalProperties": .bool(true),
      ]),
      annotations: .object([
        "title": .string(name), "readOnlyHint": .bool(readOnly),
        "destructiveHint": .bool(destructive), "idempotentHint": .bool(idempotent),
        "openWorldHint": .bool(false),
      ]))
  }

  private static func string(_ description: String) -> JSONValue {
    .object(["type": .string("string"), "description": .string(description)])
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
  private static func object(_ properties: [String: JSONValue]) -> JSONValue {
    .object([
      "type": .string("object"), "properties": .object(properties),
      "additionalProperties": .bool(false),
    ])
  }

  private static func validate(
    _ value: JSONValue, against schema: JSONValue, path: String
  ) -> String? {
    switch schema["type"]?.stringValue {
    case "object":
      guard case .object(let values) = value else { return "\(path) must be an object" }
      let properties: [String: JSONValue]
      if case .object(let declared)? = schema["properties"] { properties = declared } else {
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
      guard case .string = value else { return "\(path) must be a string" }
    case "boolean":
      guard case .bool = value else { return "\(path) must be a boolean" }
    case "number":
      guard case .number = value else { return "\(path) must be a number" }
    default: break
    }
    return nil
  }
}
