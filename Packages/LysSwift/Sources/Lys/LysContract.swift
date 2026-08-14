import Foundation

public struct LysContract: Codable, Sendable {
  public var schema: String?
  public var schemaVersion: Int
  public var app: LysApp?
  public var routes: [LysScreen]
  public var capabilities: [LysAction]
  public var contexts: [LysContext]
  public var flows: [LysFlow]

  public init(
    schemaVersion: Int = 2, app: LysApp? = nil, routes: [LysScreen] = [],
    capabilities: [LysAction] = [], contexts: [LysContext] = [], flows: [LysFlow] = []
  ) {
    schema = "../Schemas/lys-test-contract.schema.json"
    self.schemaVersion = schemaVersion
    self.app = app
    self.routes = routes
    self.capabilities = capabilities
    self.contexts = contexts
    self.flows = flows
  }

  enum CodingKeys: String, CodingKey {
    case schema = "$schema"
    case schemaVersion, app, routes, capabilities, contexts, flows
  }
}

public struct LysApp: Codable, Sendable {
  public var bundleIdentifier: String?
  public var displayName: String?
  public var entryRoutes: [String]
  public init(
    bundleIdentifier: String? = nil, displayName: String? = nil, entryRoutes: [String]
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
    self.entryRoutes = entryRoutes
  }

  public init(
    bundleIdentifier: String? = nil, displayName: String? = nil, entryRoutes: [LysScreen]
  ) {
    self.init(
      bundleIdentifier: bundleIdentifier, displayName: displayName,
      entryRoutes: entryRoutes.map(\.id))
  }

  private enum CodingKeys: String, CodingKey {
    case bundleIdentifier, displayName, entryRoutes
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
    displayName = try values.decodeIfPresent(String.self, forKey: .displayName)
    entryRoutes = try values.decodeIfPresent([String].self, forKey: .entryRoutes) ?? []
  }
}

public struct LysSelector: Codable, Hashable, Sendable {
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
}

public enum LysPredicateKind: String, Codable, Sendable {
  case route, visible, absent, enabled, selected, value, text
  case progressComplete, appIdle, noCrash
}

public struct LysPredicate: Codable, Sendable {
  public var kind: LysPredicateKind
  public var route: String?
  public var selector: LysSelector?
  public var equals: String?
  public var matches: String?

  public init(
    _ kind: LysPredicateKind, route: String? = nil, selector: LysSelector? = nil,
    equals: String? = nil, matches: String? = nil
  ) {
    self.kind = kind
    self.route = route
    self.selector = selector
    self.equals = equals
    self.matches = matches
  }

  public static func route(_ id: String) -> Self { .init(.route, route: id) }
  public static func route(_ screen: LysScreen) -> Self { .route(screen.id) }
  public static func visible(_ id: String) -> Self {
    .init(.visible, selector: .init(identifier: id))
  }
  public static func state(_ id: String, equals value: String) -> Self {
    .init(
      .value, selector: .init(identifier: "lys.state.\(id)"), equals: value)
  }
}

public struct LysScreen: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var match: [LysPredicate]
  public var terminal: Bool?

  public init(
    id: String, title: String, match: [LysPredicate]? = nil, terminal: Bool = false
  ) {
    self.id = id
    self.title = title
    self.match = match ?? [.visible("lys.screen.\(id)")]
    self.terminal = terminal ? true : nil
  }
}

public enum LysActionKind: String, Codable, Sendable {
  case tap, doubleTap, longPress, type, clear, toggle, select
  case scrollUp, scrollDown, swipe, drag, setSlider, dismiss, back
}

public enum LysRisk: String, Codable, Sendable {
  case readOnly, reversible, destructive, external
}

public struct LysParameter: Codable, Sendable {
  public var type: String
  public var required: Bool?
  public var values: [String]?
  public var sensitive: Bool?

  public init(
    type: String, required: Bool = false, values: [String]? = nil, sensitive: Bool = false
  ) {
    self.type = type
    self.required = required ? true : nil
    self.values = values
    self.sensitive = sensitive ? true : nil
  }
}

public struct LysAction: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var route: String?
  public var resultsIn: String?
  public var action: LysActionKind
  public var selector: LysSelector
  public var parameters: [String: LysParameter]?
  public var risk: LysRisk?

  public init(
    id: String, title: String, route: String? = nil, resultsIn: String? = nil,
    action: LysActionKind = .tap, selector: LysSelector? = nil,
    parameters: [String: LysParameter]? = nil, risk: LysRisk = .reversible
  ) {
    self.id = id
    self.title = title
    self.route = route
    self.resultsIn = resultsIn
    self.action = action
    self.selector = selector ?? .init(identifier: "lys.action.\(id)")
    self.parameters = parameters
    self.risk = risk
  }

  public init(
    id: String, title: String, route: LysScreen, resultsIn: LysScreen? = nil,
    action: LysActionKind = .tap, selector: LysSelector? = nil,
    parameters: [String: LysParameter]? = nil, risk: LysRisk = .reversible
  ) {
    self.init(
      id: id, title: title, route: route.id, resultsIn: resultsIn?.id, action: action,
      selector: selector, parameters: parameters, risk: risk)
  }
}

public enum LysInput: Codable, Sendable {
  case literal(String)
  case parameter(String)
  case secret(String)

  enum CodingKeys: String, CodingKey { case literal, parameter, secret }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    if let value = try values.decodeIfPresent(String.self, forKey: .literal) {
      self = .literal(value)
    } else if let value = try values.decodeIfPresent(String.self, forKey: .parameter) {
      self = .parameter(value)
    } else {
      self = .secret(try values.decode(String.self, forKey: .secret))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .literal(let value): try values.encode(value, forKey: .literal)
    case .parameter(let value): try values.encode(value, forKey: .parameter)
    case .secret(let value): try values.encode(value, forKey: .secret)
    }
  }
}

public enum LysContextMode: String, Codable, Sendable {
  case uiFlow, authenticatedSession
}

/// Controls how the host prepares the app before running a flow in this context.
/// `relaunch` preserves app data while preventing an independent flow from inheriting the
/// previous flow's in-memory navigation state. Use `preserve` only for an explicit chained flow.
public enum LysIsolationPolicy: String, Codable, Sendable {
  case relaunch, preserve
}

public struct LysAuthenticatedSession: Codable, Sendable {
  public var environment: [String: LysInput]
  public var arguments: [String]?
  public init(environment: [String: LysInput], arguments: [String]? = nil) {
    self.environment = environment
    self.arguments = arguments
  }
}

public struct LysContext: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var mode: LysContextMode
  public var isolation: LysIsolationPolicy
  public var requiredSecrets: [String]?
  public var startRoute: String?
  public var entryRoutes: [String]?
  public var prepare: [LysStep]
  public var readyWhen: [LysPredicate]
  public var session: LysAuthenticatedSession?

  public init(
    id: String, title: String, mode: LysContextMode, requiredSecrets: [String] = [],
    startRoute: String? = nil, entryRoutes: [String]? = nil,
    prepare: [LysStep] = [], readyWhen: [LysPredicate],
    session: LysAuthenticatedSession? = nil, isolation: LysIsolationPolicy = .relaunch
  ) {
    self.id = id
    self.title = title
    self.mode = mode
    self.isolation = isolation
    self.requiredSecrets = requiredSecrets.isEmpty ? nil : requiredSecrets
    self.startRoute = startRoute
    self.entryRoutes = entryRoutes
    self.prepare = prepare
    self.readyWhen = readyWhen
    self.session = session
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, mode, isolation, requiredSecrets, startRoute, entryRoutes, prepare, readyWhen
    case session
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    title = try values.decode(String.self, forKey: .title)
    mode = try values.decode(LysContextMode.self, forKey: .mode)
    isolation =
      try values.decodeIfPresent(LysIsolationPolicy.self, forKey: .isolation) ?? .relaunch
    requiredSecrets = try values.decodeIfPresent([String].self, forKey: .requiredSecrets)
    startRoute = try values.decodeIfPresent(String.self, forKey: .startRoute)
    entryRoutes = try values.decodeIfPresent([String].self, forKey: .entryRoutes)
    prepare = try values.decodeIfPresent([LysStep].self, forKey: .prepare) ?? []
    readyWhen = try values.decode([LysPredicate].self, forKey: .readyWhen)
    session = try values.decodeIfPresent(LysAuthenticatedSession.self, forKey: .session)
  }

  public static func authenticated(
    id: String, title: String, tokenEnvironmentKey: String, tokenSecret: String,
    readyWhen: [LysPredicate], isolation: LysIsolationPolicy = .relaunch
  ) -> Self {
    .init(
      id: id, title: title, mode: .authenticatedSession,
      requiredSecrets: [tokenSecret], readyWhen: readyWhen,
      session: .init(environment: [tokenEnvironmentKey: .secret(tokenSecret)]),
      isolation: isolation)
  }

  public static func signedOut(
    id: String = "signedOut", title: String = "Signed-out user",
    readyWhen: [LysPredicate], isolation: LysIsolationPolicy = .relaunch
  ) -> Self {
    .init(id: id, title: title, mode: .uiFlow, readyWhen: readyWhen, isolation: isolation)
  }

  public static func ui(
    id: String, title: String, startRoute: LysScreen, entryRoutes: [LysScreen],
    requiredSecrets: [String] = [], prepare: [LysStep], readyWhen: [LysPredicate],
    isolation: LysIsolationPolicy = .relaunch
  ) -> Self {
    .init(
      id: id, title: title, mode: .uiFlow, requiredSecrets: requiredSecrets,
      startRoute: startRoute.id, entryRoutes: entryRoutes.map(\.id), prepare: prepare,
      readyWhen: readyWhen, isolation: isolation)
  }
}

public enum LysStepKind: String, Codable, Sendable {
  case navigate, invoke, assert, repeatUntil
}

public struct LysStep: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var kind: LysStepKind
  public var route: String?
  public var capability: String?
  public var arguments: [String: LysInput]?
  public var predicate: LysPredicate?
  public var expect: [LysPredicate]?
  public var until: LysPredicate?
  public var maximumIterations: Int?
  public var steps: [LysStep]?

  public init(
    id: String, title: String, kind: LysStepKind, route: String? = nil,
    capability: String? = nil, arguments: [String: LysInput]? = nil,
    predicate: LysPredicate? = nil, expect: [LysPredicate]? = nil,
    until: LysPredicate? = nil, maximumIterations: Int? = nil, steps: [LysStep]? = nil
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

  public static func navigate(id: String, title: String, to screen: LysScreen) -> Self {
    .init(id: id, title: title, kind: .navigate, route: screen.id)
  }

  public static func invoke(
    id: String, title: String, action: LysAction,
    arguments: [String: LysInput]? = nil, expect: [LysPredicate]? = nil
  ) -> Self {
    .init(
      id: id, title: title, kind: .invoke, capability: action.id,
      arguments: arguments, expect: expect)
  }
}

public struct LysFlow: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var description: String?
  public var context: String?
  public var startRoute: String
  public var entryRoutes: [String]
  public var parameters: [String: LysParameter]?
  public var requiredSecrets: [String]?
  public var steps: [LysStep]
  public var acceptance: [LysPredicate]

  public init(
    id: String, title: String, description: String? = nil, context: String? = nil,
    startRoute: String, entryRoutes: [String], parameters: [String: LysParameter]? = nil,
    requiredSecrets: [String]? = nil, steps: [LysStep], acceptance: [LysPredicate]
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.context = context
    self.startRoute = startRoute
    self.entryRoutes = entryRoutes
    self.parameters = parameters
    self.requiredSecrets = requiredSecrets
    self.steps = steps
    self.acceptance = acceptance
  }

  public init(
    id: String, title: String, description: String? = nil, context: String? = nil,
    startRoute: LysScreen, entryRoutes: [LysScreen],
    parameters: [String: LysParameter]? = nil, requiredSecrets: [String]? = nil,
    steps: [LysStep], acceptance: [LysPredicate]
  ) {
    self.init(
      id: id, title: title, description: description, context: context,
      startRoute: startRoute.id, entryRoutes: entryRoutes.map(\.id), parameters: parameters,
      requiredSecrets: requiredSecrets, steps: steps, acceptance: acceptance)
  }
}
