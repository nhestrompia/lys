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
  private struct LaunchConfiguration {
    var executable: URL
    var workspace: URL
    var stateRoot: URL
    var developerDirectory: URL?
    var socketPath: String
    var token: String
    var startupTimeout: Duration
  }

  private struct RuntimeRequestFailure: Error {
    var underlying: Error
    var requestSent: Bool
  }

  private var process: Process?
  private var standardOutputHandle: FileHandle?
  private var standardErrorHandle: FileHandle?
  private var socketPath: String?
  private var token: String?
  private var nextID = 1
  private var launchConfiguration: LaunchConfiguration?
  private var explicitlyStopped = true
  private var launchInProgress = false

  public init() {}

  public func start(
    executable: URL, workspace: URL, stateRoot: URL, developerDirectory: URL? = nil,
    startupTimeout: Duration = .seconds(3)
  ) async throws {
    while launchInProgress {
      try await Task.sleep(for: .milliseconds(20))
    }
    launchInProgress = true
    defer { launchInProgress = false }

    let normalizedExecutable = executable.standardizedFileURL
    let normalizedWorkspace = workspace.standardizedFileURL
    let normalizedStateRoot = stateRoot.standardizedFileURL
    let previous = launchConfiguration
    await stopProcess()
    guard FileManager.default.isExecutableFile(atPath: normalizedExecutable.path) else {
      launchConfiguration = nil
      explicitlyStopped = true
      throw RuntimeControllerError.executableMissing(normalizedExecutable.path)
    }
    try FileManager.default.createDirectory(at: normalizedStateRoot, withIntermediateDirectories: true)

    let sameRuntime = previous?.executable == normalizedExecutable
      && previous?.workspace == normalizedWorkspace
      && previous?.stateRoot == normalizedStateRoot
    let socket = normalizedStateRoot.appending(path: "runtime.sock").path
    let taskToken = sameRuntime
      ? (previous?.token ?? Self.makeToken())
      : Self.makeToken()
    let configuration = LaunchConfiguration(
      executable: normalizedExecutable,
      workspace: normalizedWorkspace,
      stateRoot: normalizedStateRoot,
      developerDirectory: developerDirectory?.standardizedFileURL,
      socketPath: socket,
      token: taskToken,
      startupTimeout: startupTimeout)
    launchConfiguration = configuration
    explicitlyStopped = false

    do {
      try await launch(configuration)
    } catch {
      await stopProcess()
      throw error
    }
  }

  public func request<T: Decodable>(
    _ type: T.Type, method: String, params: JSONValue? = nil
  ) async throws -> T {
    let result = try await request(method: method, params: params)
    let data = try JSONEncoder().encode(result)
    return try JSONDecoder().decode(type, from: data)
  }

  public func request(method: String, params: JSONValue? = nil) async throws -> JSONValue {
    do {
      return try authenticatedRequest(method: method, params: params)
    } catch let failure as RuntimeRequestFailure {
      guard !failure.requestSent, canRecover else { throw failure.underlying }
      try await restartConfiguredRuntime()
      do {
        return try authenticatedRequest(method: method, params: params)
      } catch let retryFailure as RuntimeRequestFailure {
        throw retryFailure.underlying
      }
    } catch RuntimeControllerError.notRunning {
      guard canRecover else { throw RuntimeControllerError.notRunning }
      try await restartConfiguredRuntime()
      do {
        return try authenticatedRequest(method: method, params: params)
      } catch let retryFailure as RuntimeRequestFailure {
        throw retryFailure.underlying
      }
    }
  }

  public func mcpEnvironment() throws -> [String: String] {
    guard launchConfiguration != nil,
      let socketPath, let token, process?.isRunning == true, !explicitlyStopped
    else {
      throw RuntimeControllerError.notRunning
    }
    return [
      "LYS_RUNTIME_SOCKET": socketPath,
      "LYS_TASK_TOKEN": token,
    ]
  }

  public func stop() async {
    explicitlyStopped = true
    await stopProcess()
    launchConfiguration = nil
  }

  private var canRecover: Bool {
    !explicitlyStopped && launchConfiguration != nil
  }

  private func launch(_ configuration: LaunchConfiguration) async throws {
    let child = Process()
    let output = Pipe()
    let errors = Pipe()
    child.executableURL = configuration.executable
    child.arguments = [
      "--socket", configuration.socketPath,
      "--workspace", configuration.workspace.path,
      "--token", configuration.token,
    ]
    child.standardOutput = output
    child.standardError = errors
    child.environment = ProcessInfo.processInfo.environment.merging(
      configuration.developerDirectory.map { ["DEVELOPER_DIR": $0.path] } ?? [:]
    ) { _, task in task }
    let outputHandle = output.fileHandleForReading
    let errorHandle = errors.fileHandleForReading
    outputHandle.readabilityHandler = { handle in
      if handle.availableData.isEmpty { handle.readabilityHandler = nil }
    }
    errorHandle.readabilityHandler = { handle in
      if handle.availableData.isEmpty { handle.readabilityHandler = nil }
    }
    do {
      try child.run()
    } catch {
      outputHandle.readabilityHandler = nil
      errorHandle.readabilityHandler = nil
      throw error
    }
    process = child
    standardOutputHandle = outputHandle
    standardErrorHandle = errorHandle
    socketPath = configuration.socketPath
    token = configuration.token

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: configuration.startupTimeout)
    while clock.now < deadline {
      if FileManager.default.fileExists(atPath: configuration.socketPath) {
        do {
          _ = try authenticatedRequest(method: "workspace.describe", params: nil)
          return
        } catch {
          if !child.isRunning { break }
        }
      }
      try await Task.sleep(for: .milliseconds(40))
    }
    await stopProcess()
    throw RuntimeControllerError.startupTimedOut
  }

  private func restartConfiguredRuntime() async throws {
    while launchInProgress {
      try await Task.sleep(for: .milliseconds(20))
    }
    guard let configuration = launchConfiguration, !explicitlyStopped else {
      throw RuntimeControllerError.notRunning
    }
    launchInProgress = true
    defer { launchInProgress = false }
    await stopProcess()
    try await launch(configuration)
  }

  private func stopProcess() async {
    let child = process
    standardOutputHandle?.readabilityHandler = nil
    standardErrorHandle?.readabilityHandler = nil
    standardOutputHandle = nil
    standardErrorHandle = nil
    if let child {
      child.interrupt()
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while child.isRunning && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(50))
      }
      if child.isRunning { child.terminate() }
    }
    if let socketPath { unlink(socketPath) }
    else if let socketPath = launchConfiguration?.socketPath { unlink(socketPath) }
    process = nil
    socketPath = nil
    token = nil
  }

  private func authenticatedRequest(method: String, params: JSONValue?) throws -> JSONValue {
    guard let socketPath, let token, process?.isRunning == true else {
      throw RuntimeControllerError.notRunning
    }
    let connection: UnixSocketConnection
    do {
      connection = try UnixSocketConnection.connect(path: socketPath)
    } catch {
      throw RuntimeRequestFailure(underlying: error, requestSent: false)
    }
    var requestSent = false
    do {
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
      requestSent = true
      try connection.send(.init(id: .int(id), method: method, params: params))
      let response = try connection.receive()
      if let error = response.error { throw RuntimeControllerError.remote(error) }
      return response.result ?? .null
    } catch let error as RuntimeControllerError {
      throw error
    } catch {
      throw RuntimeRequestFailure(underlying: error, requestSent: requestSent)
    }
  }

  private static func makeToken() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "")
  }
}
