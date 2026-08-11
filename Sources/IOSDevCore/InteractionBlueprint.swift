import Foundation

/// Optional, repository-owned interaction knowledge. Operate can discover the same information at
/// runtime; a blueprint supplies stable names, setup/authentication, and acceptance criteria when a
/// team or coding agent wants a contractual flow.
public struct InteractionBlueprint: Codable, Sendable {
  public var schemaVersion: Int
  public var app: BlueprintApp?
  public var routes: [BlueprintRoute]?
  public var capabilities: [BlueprintCapability]?
  public var contexts: [BlueprintContext]?
  public var flows: [BlueprintFlow]

  public init(
    schemaVersion: Int = 1, app: BlueprintApp? = nil, routes: [BlueprintRoute]? = nil,
    capabilities: [BlueprintCapability]? = nil, contexts: [BlueprintContext]? = nil,
    flows: [BlueprintFlow]
  ) {
    self.schemaVersion = schemaVersion
    self.app = app
    self.routes = routes
    self.capabilities = capabilities
    self.contexts = contexts
    self.flows = flows
  }

  public static func load(from url: URL) throws -> Self {
    let blueprint = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    try blueprint.validate()
    return blueprint
  }

  public func validate() throws {
    guard schemaVersion == 1 else {
      throw RPCError(code: -32110, message: "Unsupported Operate blueprint schema version")
    }
    try requireUnique((routes ?? []).map(\.id), kind: "route")
    try requireUnique((capabilities ?? []).map(\.id), kind: "capability")
    try requireUnique((contexts ?? []).map(\.id), kind: "context")
    try requireUnique(flows.map(\.id), kind: "flow")

    let routeIDs = Set((routes ?? []).map(\.id))
    let capabilityIDs = Set((capabilities ?? []).map(\.id))
    let contextIDs = Set((contexts ?? []).map(\.id))
    for route in routes ?? [] {
      guard !route.match.isEmpty else {
        throw invalid("Route \(route.id) requires match predicates")
      }
      guard !route.match.contains(where: { $0.kind == .route }) else {
        throw invalid("Route \(route.id) cannot match another route recursively")
      }
      try validate(predicates: route.match, owner: "Route \(route.id)", routes: routeIDs)
    }
    for capability in capabilities ?? [] {
      if let route = capability.route, !routeIDs.contains(route) {
        throw invalid("Capability \(capability.id) references unknown route \(route)")
      }
      if let result = capability.resultsIn, !routeIDs.contains(result) {
        throw invalid("Capability \(capability.id) references unknown result route \(result)")
      }
      try capability.selector.validate(owner: "Capability \(capability.id)")
      for (name, parameter) in capability.parameters ?? [:] {
        try parameter.validate(owner: "Capability \(capability.id) parameter \(name)")
      }
    }
    for context in contexts ?? [] {
      try validate(
        steps: context.prepare, owner: "Context \(context.id)", routes: routeIDs,
        capabilities: capabilityIDs)
      guard !context.readyWhen.isEmpty else {
        throw invalid("Context \(context.id) requires a deterministic readyWhen condition")
      }
      try validate(
        predicates: context.readyWhen, owner: "Context \(context.id)", routes: routeIDs)
    }
    for flow in flows {
      guard !flow.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalid("Flow \(flow.id) requires a title")
      }
      if let context = flow.context, !contextIDs.contains(context) {
        throw invalid("Flow \(flow.id) references unknown context \(context)")
      }
      if let startRoute = flow.startRoute, !routeIDs.contains(startRoute) {
        throw invalid("Flow \(flow.id) references unknown start route \(startRoute)")
      }
      guard !flow.steps.isEmpty else { throw invalid("Flow \(flow.id) requires steps") }
      guard !flow.acceptance.isEmpty else {
        throw invalid("Flow \(flow.id) requires deterministic acceptance criteria")
      }
      for (name, parameter) in flow.parameters ?? [:] {
        try parameter.validate(owner: "Flow \(flow.id) parameter \(name)")
      }
      try validate(
        steps: flow.steps, owner: "Flow \(flow.id)", routes: routeIDs,
        capabilities: capabilityIDs)
      try validate(predicates: flow.acceptance, owner: "Flow \(flow.id)", routes: routeIDs)
    }
  }

  private func validate(
    steps: [BlueprintStep], owner: String, routes: Set<String>, capabilities: Set<String>
  ) throws {
    guard !steps.isEmpty else { return }
    try requireUnique(steps.map(\.id), kind: "step")
    for step in steps {
      for (name, input) in step.arguments ?? [:] {
        try input.validate(owner: "\(owner) step \(step.id) argument \(name)")
      }
      switch step.kind {
      case .invoke:
        guard let capability = step.capability, capabilities.contains(capability) else {
          throw invalid("\(owner) step \(step.id) references an unknown capability")
        }
      case .navigate:
        guard let route = step.route, routes.contains(route) else {
          throw invalid("\(owner) step \(step.id) references an unknown route")
        }
      case .assert:
        guard step.predicate != nil else {
          throw invalid("\(owner) assertion step \(step.id) requires a predicate")
        }
      case .repeatUntil:
        guard let maximum = step.maximumIterations, (1...1_000).contains(maximum),
          step.until != nil, let nested = step.steps, !nested.isEmpty
        else {
          throw invalid(
            "\(owner) repeat step \(step.id) requires until, steps, and maximumIterations 1...1000")
        }
        try validate(
          steps: nested, owner: "\(owner) repeat \(step.id)", routes: routes,
          capabilities: capabilities)
      }
      if let predicate = step.predicate {
        try predicate.validate(owner: "\(owner) step \(step.id)")
        try validate(
          predicates: [predicate], owner: "\(owner) step \(step.id)", routes: routes)
      }
      if let until = step.until {
        try until.validate(owner: "\(owner) step \(step.id)")
        try validate(
          predicates: [until], owner: "\(owner) step \(step.id)", routes: routes)
      }
      try validate(
        predicates: step.expect ?? [], owner: "\(owner) step \(step.id)", routes: routes)
    }
  }

  private func validate(
    predicates: [BlueprintPredicate]?, owner: String, routes: Set<String>
  ) throws {
    for predicate in predicates ?? [] {
      try predicate.validate(owner: owner)
      if predicate.kind == .route, let route = predicate.route, !routes.contains(route) {
        throw invalid("\(owner) references unknown route \(route)")
      }
    }
  }

  private func requireUnique(_ ids: [String], kind: String) throws {
    guard ids.allSatisfy(BlueprintIdentifier.isValid) else {
      throw invalid(
        "Every \(kind) ID must use dot-separated letters, numbers, underscores, or hyphens")
    }
    guard Set(ids).count == ids.count else {
      throw invalid("Blueprint contains duplicate \(kind) IDs")
    }
  }

  private func invalid(_ message: String) -> RPCError { .init(code: -32111, message: message) }
}

public enum InteractionBlueprintDiscovery {
  public static let relativePath = ".operate/blueprint.json"

  public static func load(in workspace: URL) throws -> InteractionBlueprint? {
    let url = workspace.appending(path: relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try InteractionBlueprint.load(from: url)
  }
}

public struct BlueprintApp: Codable, Sendable {
  public var bundleIdentifier: String?
  public var displayName: String?

  public init(bundleIdentifier: String? = nil, displayName: String? = nil) {
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
  }
}

public struct BlueprintRoute: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var match: [BlueprintPredicate]

  public init(id: String, title: String, match: [BlueprintPredicate]) {
    self.id = id
    self.title = title
    self.match = match
  }
}

public enum BlueprintActionKind: String, Codable, CaseIterable, Sendable {
  case tap, doubleTap, longPress, type, clear, toggle, select
  case scrollUp, scrollDown, swipe, drag, setSlider, dismiss, back
}

public struct BlueprintCapability: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var route: String?
  public var resultsIn: String?
  public var action: BlueprintActionKind
  public var selector: BlueprintSelector
  public var parameters: [String: BlueprintParameter]?
  public var risk: BlueprintRisk?

  public init(
    id: String, title: String, route: String? = nil, resultsIn: String? = nil,
    action: BlueprintActionKind,
    selector: BlueprintSelector, parameters: [String: BlueprintParameter]? = nil,
    risk: BlueprintRisk? = nil
  ) {
    self.id = id
    self.title = title
    self.route = route
    self.resultsIn = resultsIn
    self.action = action
    self.selector = selector
    self.parameters = parameters
    self.risk = risk
  }
}

public enum BlueprintRisk: String, Codable, Sendable {
  case readOnly, reversible, destructive, external
}

public struct BlueprintParameter: Codable, Sendable {
  public var type: String
  public var required: Bool?
  public var values: [String]?
  public var sensitive: Bool?

  public init(
    type: String, required: Bool? = nil, values: [String]? = nil, sensitive: Bool? = nil
  ) {
    self.type = type
    self.required = required
    self.values = values
    self.sensitive = sensitive
  }

  fileprivate func validate(owner: String) throws {
    guard ["string", "number", "boolean", "enum"].contains(type) else {
      throw RPCError(code: -32111, message: "\(owner) has unsupported type \(type)")
    }
    if type == "enum", values?.isEmpty != false {
      throw RPCError(code: -32111, message: "\(owner) enum requires values")
    }
  }
}

public struct BlueprintSelector: Codable, Hashable, Sendable {
  public var identifier: String?
  public var role: String?
  public var name: String?
  public var text: String?
  public var above: String?
  public var below: String?
  public var descendantOf: String?
  public var index: Int?

  public init(
    identifier: String? = nil, role: String? = nil, name: String? = nil,
    text: String? = nil, above: String? = nil, below: String? = nil,
    descendantOf: String? = nil, index: Int? = nil
  ) {
    self.identifier = identifier
    self.role = role
    self.name = name
    self.text = text
    self.above = above
    self.below = below
    self.descendantOf = descendantOf
    self.index = index
  }

  fileprivate func validate(owner: String) throws {
    guard [identifier, name, text].contains(where: { $0?.isEmpty == false }) else {
      throw RPCError(code: -32111, message: "\(owner) requires identifier, name, or text")
    }
    if let index, index < 0 {
      throw RPCError(code: -32111, message: "\(owner) selector index cannot be negative")
    }
  }
}

public struct BlueprintContext: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var requiredSecrets: [String]?
  public var prepare: [BlueprintStep]
  public var readyWhen: [BlueprintPredicate]

  public init(
    id: String, title: String, requiredSecrets: [String]? = nil,
    prepare: [BlueprintStep], readyWhen: [BlueprintPredicate]
  ) {
    self.id = id
    self.title = title
    self.requiredSecrets = requiredSecrets
    self.prepare = prepare
    self.readyWhen = readyWhen
  }
}

public struct BlueprintFlow: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var description: String?
  public var context: String?
  public var startRoute: String?
  public var parameters: [String: BlueprintParameter]?
  public var steps: [BlueprintStep]
  public var acceptance: [BlueprintPredicate]

  public init(
    id: String, title: String, description: String? = nil, context: String? = nil,
    startRoute: String? = nil, parameters: [String: BlueprintParameter]? = nil,
    steps: [BlueprintStep], acceptance: [BlueprintPredicate]
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.context = context
    self.startRoute = startRoute
    self.parameters = parameters
    self.steps = steps
    self.acceptance = acceptance
  }
}

public enum BlueprintStepKind: String, Codable, Sendable {
  case navigate, invoke, assert, repeatUntil
}

public struct BlueprintStep: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var kind: BlueprintStepKind
  public var route: String?
  public var capability: String?
  public var arguments: [String: BlueprintInput]?
  public var predicate: BlueprintPredicate?
  public var expect: [BlueprintPredicate]?
  public var until: BlueprintPredicate?
  public var maximumIterations: Int?
  public var steps: [BlueprintStep]?

  public init(
    id: String, title: String, kind: BlueprintStepKind, route: String? = nil,
    capability: String? = nil, arguments: [String: BlueprintInput]? = nil,
    predicate: BlueprintPredicate? = nil, expect: [BlueprintPredicate]? = nil,
    until: BlueprintPredicate? = nil, maximumIterations: Int? = nil,
    steps: [BlueprintStep]? = nil
  ) {
    self.id = id
    self.title = title
    self.kind = kind
    self.route = route
    self.capability = capability
    self.arguments = arguments
    self.predicate = predicate
    self.expect = expect
    self.until = until
    self.maximumIterations = maximumIterations
    self.steps = steps
  }
}

public struct BlueprintInput: Codable, Sendable {
  public var literal: JSONValue?
  public var parameter: String?
  public var secret: String?

  public init(literal: JSONValue? = nil, parameter: String? = nil, secret: String? = nil) {
    self.literal = literal
    self.parameter = parameter
    self.secret = secret
  }

  fileprivate func validate(owner: String) throws {
    let sourceCount = [literal != nil, parameter != nil, secret != nil].filter { $0 }.count
    guard sourceCount == 1 else {
      throw RPCError(
        code: -32111,
        message: "\(owner) must declare exactly one of literal, parameter, or secret")
    }
    if let parameter, !BlueprintIdentifier.isValid(parameter) {
      throw RPCError(code: -32111, message: "\(owner) has an invalid parameter ID")
    }
    if let secret, !BlueprintIdentifier.isValid(secret) {
      throw RPCError(code: -32111, message: "\(owner) has an invalid secret ID")
    }
  }
}

public enum BlueprintPredicateKind: String, Codable, Sendable {
  case route, visible, absent, enabled, selected, value, text, progressComplete, appIdle, noCrash
}

public struct BlueprintPredicate: Codable, Sendable {
  public var kind: BlueprintPredicateKind
  public var route: String?
  public var selector: BlueprintSelector?
  public var equals: String?
  public var matches: String?

  public init(
    kind: BlueprintPredicateKind, route: String? = nil, selector: BlueprintSelector? = nil,
    equals: String? = nil, matches: String? = nil
  ) {
    self.kind = kind
    self.route = route
    self.selector = selector
    self.equals = equals
    self.matches = matches
  }

  fileprivate func validate(owner: String) throws {
    switch kind {
    case .route:
      guard route?.isEmpty == false else {
        throw RPCError(code: -32111, message: "\(owner) route predicate requires route")
      }
    case .visible, .absent, .enabled, .selected:
      guard let selector else {
        throw RPCError(code: -32111, message: "\(owner) \(kind.rawValue) requires selector")
      }
      try selector.validate(owner: owner)
    case .value:
      guard let selector, equals != nil else {
        throw RPCError(code: -32111, message: "\(owner) value requires selector and equals")
      }
      try selector.validate(owner: owner)
    case .text:
      guard let selector, matches?.isEmpty == false else {
        throw RPCError(code: -32111, message: "\(owner) text requires selector and matches")
      }
      try selector.validate(owner: owner)
    case .progressComplete, .appIdle, .noCrash: break
    }
  }
}

private enum BlueprintIdentifier {
  static func isValid(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 128 else { return false }
    return value.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.contains($0) || [".", "_", "-"].contains(Character($0))
    }
  }
}
