import Foundation

public enum Lys {
  public static let registry = LysRegistry()

  public static func configure(_ app: LysApp) {
    registry.configure(app)
  }

  public static func register(_ screen: LysScreen) { registry.register(screen) }
  public static func register(_ action: LysAction) { registry.register(action) }
  public static func register(_ context: LysContext) { registry.register(context) }
  public static func register(_ flow: LysFlow) { registry.register(flow) }

  /// Exports the small generated contract consumed by the Lys desktop runner. Teams can call this
  /// from a test or tooling target; application production behavior is never changed.
  public static func exportContract(to url: URL) throws {
    let data = try registry.encodedContract()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }
}

public final class LysRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var app: LysApp?
  private var screens: [String: LysScreen] = [:]
  private var actions: [String: LysAction] = [:]
  private var contexts: [String: LysContext] = [:]
  private var flows: [String: LysFlow] = [:]

  public init() {}

  public func configure(_ app: LysApp) { withLock { self.app = app } }
  public func register(_ screen: LysScreen) { withLock { screens[screen.id] = screen } }
  public func register(_ action: LysAction) { withLock { actions[action.id] = action } }
  public func register(_ context: LysContext) { withLock { contexts[context.id] = context } }
  public func register(_ flow: LysFlow) { withLock { flows[flow.id] = flow } }

  public func contract() -> LysContract {
    withLock {
      LysContract(
        app: app, routes: screens.values.sorted { $0.id < $1.id },
        capabilities: actions.values.sorted { $0.id < $1.id },
        contexts: contexts.values.sorted { $0.id < $1.id },
        flows: flows.values.sorted { $0.id < $1.id })
        .expandingRecoverableFlowEntries()
    }
  }

  public func encodedContract() throws -> Data {
    let contract = contract()
    try contract.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(contract)
  }

  @discardableResult
  private func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}

public enum LysTestSession {
  /// The context requested by the host for the current test launch. The app uses this value to
  /// choose its own router/session setup; Lys never reaches into product navigation directly.
  public static var contextID: String? {
    guard isEnabled else { return nil }
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-LysContext"), arguments.indices.contains(index + 1)
    else { return nil }
    let value = arguments[index + 1]
    return value.isEmpty ? nil : value
  }

  /// True when this launch is the host-owned normalization boundary before an independent flow.
  public static var resetRequested: Bool {
    isEnabled && ProcessInfo.processInfo.arguments.contains("-LysReset")
  }

  /// Returns whether this launch asks the app to normalize the requested context. Passing a
  /// context ID prevents a stale or unrelated launch argument from changing app state.
  public static func resetRequested(for contextID: String) -> Bool {
    resetRequested && self.contextID == contextID
  }

  public static var isEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains("-LysTesting")
  }

  /// Reads a host-injected test credential. The application decides how to exchange or restore
  /// it; Lys never logs, persists, or returns it to an agent.
  public static func credential(environmentKey: String) -> String? {
    guard isEnabled else { return nil }
    return ProcessInfo.processInfo.environment[environmentKey]
  }
}
