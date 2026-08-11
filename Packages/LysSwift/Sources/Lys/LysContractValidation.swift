import Foundation

public struct LysContractValidationError: Error, LocalizedError, Equatable, Sendable {
  public let message: String

  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}

extension LysContract {
  /// Validates cross-references and deterministic execution constraints before a contract is
  /// exported. The desktop runner repeats these checks at load time; catching them in the SDK
  /// keeps malformed flows out of source control.
  public func validate() throws {
    guard schemaVersion == 1 else { throw invalid("Unsupported schemaVersion \(schemaVersion)") }
    try unique(routes.map(\.id), kind: "screen")
    try unique(capabilities.map(\.id), kind: "action")
    try unique(contexts.map(\.id), kind: "context")
    try unique(flows.map(\.id), kind: "flow")
    guard !flows.isEmpty else { throw invalid("A contract requires at least one flow") }

    let screenIDs = Set(routes.map(\.id))
    let actionIDs = Set(capabilities.map(\.id))
    let contextIDs = Set(contexts.map(\.id))

    for screen in routes {
      guard !screen.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalid("Screen \(screen.id) requires a title")
      }
      guard !screen.match.isEmpty else { throw invalid("Screen \(screen.id) requires match predicates") }
      guard !screen.match.contains(where: { $0.kind == .route }) else {
        throw invalid("Screen \(screen.id) cannot recursively match a route")
      }
      try validate(screen.match, owner: "Screen \(screen.id)", screens: screenIDs)
    }

    for action in capabilities {
      guard !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalid("Action \(action.id) requires a title")
      }
      try validate(action.selector, owner: "Action \(action.id)")
      if let screen = action.route, !screenIDs.contains(screen) {
        throw invalid("Action \(action.id) references unknown screen \(screen)")
      }
      if let result = action.resultsIn, !screenIDs.contains(result) {
        throw invalid("Action \(action.id) references unknown result screen \(result)")
      }
      for (name, parameter) in action.parameters ?? [:] {
        try validate(parameter, owner: "Action \(action.id) parameter \(name)")
      }
    }

    for context in contexts {
      guard !context.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalid("Context \(context.id) requires a title")
      }
      guard !context.readyWhen.isEmpty else {
        throw invalid("Context \(context.id) requires readyWhen predicates")
      }
      try unique(context.requiredSecrets ?? [], kind: "secret")
      switch context.mode {
      case .uiFlow:
        guard context.session == nil else {
          throw invalid("UI context \(context.id) cannot declare a session fixture")
        }
      case .authenticatedSession:
        guard let session = context.session, !session.environment.isEmpty else {
          throw invalid("Authenticated context \(context.id) requires a session environment")
        }
        let requiredSecrets = Set(context.requiredSecrets ?? [])
        for (key, input) in session.environment {
          guard validEnvironmentKey(key) else {
            throw invalid("Authenticated context \(context.id) has invalid environment key \(key)")
          }
          try validate(input, owner: "Authenticated context \(context.id) environment \(key)")
          if case .secret(let secret) = input, !requiredSecrets.contains(secret) {
            throw invalid("Authenticated context \(context.id) must declare secret \(secret)")
          }
        }
      }
      try validate(
        context.prepare, owner: "Context \(context.id)", screens: screenIDs, actions: actionIDs)
      let undeclaredContextSecrets = secrets(in: context.prepare)
        .subtracting(context.requiredSecrets ?? [])
      if let secret = undeclaredContextSecrets.sorted().first {
        throw invalid("Context \(context.id) must declare step secret \(secret)")
      }
      try validate(context.readyWhen, owner: "Context \(context.id)", screens: screenIDs)
    }

    for flow in flows {
      guard !flow.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalid("Flow \(flow.id) requires a title")
      }
      if let context = flow.context, !contextIDs.contains(context) {
        throw invalid("Flow \(flow.id) references unknown context \(context)")
      }
      if let start = flow.startRoute, !screenIDs.contains(start) {
        throw invalid("Flow \(flow.id) references unknown start screen \(start)")
      }
      guard !flow.steps.isEmpty else { throw invalid("Flow \(flow.id) requires steps") }
      guard !flow.acceptance.isEmpty else {
        throw invalid("Flow \(flow.id) requires deterministic acceptance predicates")
      }
      for (name, parameter) in flow.parameters ?? [:] {
        try validate(parameter, owner: "Flow \(flow.id) parameter \(name)")
      }
      try unique(flow.requiredSecrets ?? [], kind: "secret")
      let undeclaredFlowSecrets = secrets(in: flow.steps).subtracting(flow.requiredSecrets ?? [])
      if let secret = undeclaredFlowSecrets.sorted().first {
        throw invalid("Flow \(flow.id) must declare step secret \(secret)")
      }
      try validate(flow.steps, owner: "Flow \(flow.id)", screens: screenIDs, actions: actionIDs)
      try validate(flow.acceptance, owner: "Flow \(flow.id)", screens: screenIDs)
    }
  }

  private func validate(
    _ steps: [LysStep], owner: String, screens: Set<String>, actions: Set<String>
  ) throws {
    try unique(steps.map(\.id), kind: "step in \(owner)")
    for step in steps {
      guard !step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalid("\(owner) step \(step.id) requires a title")
      }
      for (name, input) in step.arguments ?? [:] {
        try validate(input, owner: "\(owner) step \(step.id) argument \(name)")
      }
      switch step.kind {
      case .navigate:
        guard let route = step.route, screens.contains(route) else {
          throw invalid("\(owner) step \(step.id) references an unknown screen")
        }
      case .invoke:
        guard let action = step.capability, actions.contains(action) else {
          throw invalid("\(owner) step \(step.id) references an unknown action")
        }
      case .assert:
        guard step.predicate != nil else {
          throw invalid("\(owner) step \(step.id) requires a predicate")
        }
      case .repeatUntil:
        guard let maximum = step.maximumIterations, (1...1_000).contains(maximum),
          step.until != nil, let nested = step.steps, !nested.isEmpty
        else {
          throw invalid("\(owner) repeat step \(step.id) requires until, steps, and a 1...1000 limit")
        }
        try validate(nested, owner: "\(owner) repeat \(step.id)", screens: screens, actions: actions)
      }
      if let predicate = step.predicate {
        try validate([predicate], owner: "\(owner) step \(step.id)", screens: screens)
      }
      if let until = step.until {
        try validate([until], owner: "\(owner) step \(step.id)", screens: screens)
      }
      try validate(step.expect ?? [], owner: "\(owner) step \(step.id)", screens: screens)
    }
  }

  private func validate(_ predicates: [LysPredicate], owner: String, screens: Set<String>) throws {
    for predicate in predicates {
      switch predicate.kind {
      case .route:
        guard let route = predicate.route, screens.contains(route) else {
          throw invalid("\(owner) references an unknown route")
        }
      case .visible, .absent, .enabled, .selected:
        guard let selector = predicate.selector else {
          throw invalid("\(owner) \(predicate.kind.rawValue) predicate requires a selector")
        }
        try validate(selector, owner: owner)
      case .value:
        guard let selector = predicate.selector, predicate.equals != nil else {
          throw invalid("\(owner) value predicate requires a selector and equals")
        }
        try validate(selector, owner: owner)
      case .text:
        guard let selector = predicate.selector, predicate.matches?.isEmpty == false else {
          throw invalid("\(owner) text predicate requires a selector and matches")
        }
        try validate(selector, owner: owner)
      case .progressComplete, .appIdle, .noCrash: break
      }
    }
  }

  private func validate(_ selector: LysSelector, owner: String) throws {
    guard [selector.identifier, selector.name, selector.text].contains(where: { $0?.isEmpty == false }) else {
      throw invalid("\(owner) selector requires identifier, name, or text")
    }
    if let index = selector.index, index < 0 { throw invalid("\(owner) selector index cannot be negative") }
  }

  private func validate(_ parameter: LysParameter, owner: String) throws {
    guard ["string", "number", "boolean", "enum"].contains(parameter.type) else {
      throw invalid("\(owner) has unsupported type \(parameter.type)")
    }
    if parameter.type == "enum", parameter.values?.isEmpty != false {
      throw invalid("\(owner) enum requires values")
    }
  }

  private func validate(_ input: LysInput, owner: String) throws {
    switch input {
    case .literal: break
    case .parameter(let id), .secret(let id):
      guard validIdentifier(id) else { throw invalid("\(owner) contains an invalid ID") }
    }
  }

  private func unique(_ ids: [String], kind: String) throws {
    guard ids.allSatisfy(validIdentifier) else { throw invalid("Every \(kind) ID must be stable and dot-separated") }
    guard Set(ids).count == ids.count else { throw invalid("Duplicate \(kind) IDs are not allowed") }
  }

  private func secrets(in steps: [LysStep]) -> Set<String> {
    var result = Set(
      steps.flatMap { step in
        (step.arguments ?? [:]).values.compactMap { input -> String? in
          if case .secret(let value) = input { return value }
          return nil
        }
      })
    for step in steps { result.formUnion(secrets(in: step.steps ?? [])) }
    return result
  }

  private func validIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 128 else { return false }
    return value.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
    }
  }

  private func validEnvironmentKey(_ value: String) -> Bool {
    guard let first = value.unicodeScalars.first,
      CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first)
    else { return false }
    return value.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains($0)
    }
  }

  private func invalid(_ message: String) -> LysContractValidationError { .init(message) }
}
