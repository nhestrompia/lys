import Darwin
import Foundation

public enum RuntimeControllerError: Error, LocalizedError {
  case executableMissing(String)
  case startupTimedOut
  case notRunning
  case authenticationFailed(String)
  case remote(RPCError)

  public var errorDescription: String? {
    switch self {
    case .executableMissing(let path): "The bundled lysd executable is missing at \(path)"
    case .startupTimedOut: "lysd did not create its task socket before the startup deadline"
    case .notRunning: "The task runtime is not running"
    case .authenticationFailed(let message): "Runtime authentication failed: \(message)"
    case .remote(let error): error.message
    }
  }
}

public actor RuntimeController {
  private var process: Process?
  private var socketPath: String?
  private var token: String?
  private var nextID = 1

  public init() {}

  public func start(
    executable: URL, workspace: URL, stateRoot: URL, developerDirectory: URL? = nil,
    startupTimeout: Duration = .seconds(3)
  ) async throws {
    await stop()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw RuntimeControllerError.executableMissing(executable.path)
    }
    try FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)
    let socket = stateRoot.appending(path: "runtime-\(UUID().uuidString.prefix(12)).sock").path
    let taskToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let child = Process()
    let output = Pipe()
    let errors = Pipe()
    child.executableURL = executable
    child.arguments = [
      "--socket", socket, "--workspace", workspace.path, "--token", taskToken,
    ]
    child.standardOutput = output
    child.standardError = errors
    child.environment = ProcessInfo.processInfo.environment.merging(
      developerDirectory.map { ["DEVELOPER_DIR": $0.path] } ?? [:]
    ) { _, task in task }
    output.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
    errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
    try child.run()
    process = child
    socketPath = socket
    token = taskToken

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: startupTimeout)
    while clock.now < deadline {
      if FileManager.default.fileExists(atPath: socket) {
        do {
          _ = try authenticatedRequest(method: "workspace.describe", params: nil)
          return
        } catch {
          if !child.isRunning { break }
        }
      }
      try await Task.sleep(for: .milliseconds(40))
    }
    await stop()
    throw RuntimeControllerError.startupTimedOut
  }

  public func request<T: Decodable>(
    _ type: T.Type, method: String, params: JSONValue? = nil
  ) throws -> T {
    let result = try authenticatedRequest(method: method, params: params)
    let data = try JSONEncoder().encode(result)
    return try JSONDecoder().decode(type, from: data)
  }

  public func request(method: String, params: JSONValue? = nil) throws -> JSONValue {
    try authenticatedRequest(method: method, params: params)
  }

  public func mcpEnvironment() throws -> [String: String] {
    guard let socketPath, let token, process?.isRunning == true else {
      throw RuntimeControllerError.notRunning
    }
    return ["LYS_RUNTIME_SOCKET": socketPath, "LYS_TASK_TOKEN": token]
  }

  public func stop() async {
    guard let child = process else { return }
    child.interrupt()
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while child.isRunning && ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
    if child.isRunning { child.terminate() }
    if let socketPath { unlink(socketPath) }
    process = nil
    socketPath = nil
    token = nil
  }

  private func authenticatedRequest(method: String, params: JSONValue?) throws -> JSONValue {
    guard let socketPath, let token, process?.isRunning == true else {
      throw RuntimeControllerError.notRunning
    }
    let connection = try UnixSocketConnection.connect(path: socketPath)
    try connection.send(
      .init(
        id: .int(0), method: "runtime.authenticate",
        params: .object(["token": .string(token)])))
    let authentication = try connection.receive()
    if let error = authentication.error {
      throw RuntimeControllerError.authenticationFailed(error.message)
    }
    let id = nextID
    nextID += 1
    try connection.send(.init(id: .int(id), method: method, params: params))
    let response = try connection.receive()
    if let error = response.error { throw RuntimeControllerError.remote(error) }
    return response.result ?? .null
  }
}
