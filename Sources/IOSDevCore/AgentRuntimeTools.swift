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
        "Start or continue a recoverable host-owned app-testing journey. Call first with only goal. Then choose exact opaque IDs from currentUI.actions and submit at most one screen-changing interaction per call so the next action catalog is fresh. Never invent labels, roles, selectors, or coordinates. A rejected action refreshes the catalog without ending the journey.",
        properties: [
          "goal": string("Natural-language user outcome to verify"),
          "journeyID": string("ID returned by an earlier journey.run call"),
          "complete": boolean("Finish the journey after these steps and capture final evidence"),
          "steps": array(
            items: object([
              "id": string("Stable step ID"), "title": string("Short user-visible step title"),
              "criterionID": string("Acceptance criterion ID"),
              "actionID": string("Exact opaque ID from the latest currentUI.actions array"),
              "selector": object([
                "identifier": string("Legacy accessibility identifier fallback"),
                "label": string("Legacy unique accessibility label fallback"),
                "type": string("Legacy accessibility role fallback"),
              ]),
              "action": string("One action listed by the selected actionID"),
              "text": string("Text for a type action"),
              "expectScreenChanged": boolean("Require a different host fingerprint after the action"),
              "assertVisible": boolean("With no action, assert actionID is visible. Legacy action steps interpret this as expectScreenChanged."),
            ], required: ["id", "title", "actionID"]))
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
        "ui.snapshot", "Inspect the current app. Returns host-issued actions before hierarchy details; use their opaque IDs instead of creating selectors.",
        properties: [:], readOnly: true),
      tool(
        "ui.actions", "List every currently host-resolved tap, type, clear, and scroll capability with an opaque screen-bound actionID.",
        properties: [:], readOnly: true),
      tool(
        "ui.find", "Find semantic UI elements in the current app using an accessibility identifier or unique label and type.",
        properties: ["selector": selectorSchema], required: ["selector"], readOnly: true),
      tool(
        "ui.perform", "Perform one action using an exact actionID from the latest ui.actions response. The ID is bound to the current screen and safely becomes stale after navigation.",
        properties: [
          "actionID": string("Exact opaque ID returned by ui.actions"),
          "selector": selectorSchema, "action": string("An action advertised for this actionID"),
          "text": string("Text for type actions"),
        ], required: ["actionID", "action"], readOnly: false, destructive: false),
      tool(
        "ui.wait", "Wait with bounded automatic retry for a semantic UI selector.",
        properties: [
          "selector": selectorSchema, "timeoutSeconds": number("Timeout from 0.2 to 30 seconds"),
        ], required: ["selector"], readOnly: true),
      tool(
        "ui.assert", "Record deterministic evidence that a current host-issued actionID is visible.",
        properties: [
          "criterionID": string("Acceptance criterion ID"),
          "actionID": string("Exact opaque ID returned by ui.actions"),
          "selector": selectorSchema,
        ], required: ["criterionID", "actionID"], readOnly: true),
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
      return [common[0], testListTool, testRunTool]
        + common.filter { ["verification.status", "verification.submit"].contains($0.name) }
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
  private static func object(
    _ properties: [String: JSONValue], required: [String] = []
  ) -> JSONValue {
    .object([
      "type": .string("object"), "properties": .object(properties),
      "required": .array(required.map(JSONValue.string)),
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
