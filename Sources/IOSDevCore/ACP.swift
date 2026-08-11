import Foundation

public enum ACPProtocol {
  public static let version = 1
}

public struct ACPFileSystemCapabilities: Codable, Equatable, Sendable {
  public var readTextFile: Bool
  public var writeTextFile: Bool
  public init(readTextFile: Bool = true, writeTextFile: Bool = false) {
    self.readTextFile = readTextFile
    self.writeTextFile = writeTextFile
  }
}

public struct ACPClientCapabilities: Codable, Equatable, Sendable {
  public var fs: ACPFileSystemCapabilities
  public var terminal: Bool
  public init(
    fs: ACPFileSystemCapabilities = .init(), terminal: Bool = false
  ) {
    self.fs = fs
    self.terminal = terminal
  }
}

public struct ACPImplementation: Codable, Equatable, Sendable {
  public var name: String
  public var title: String
  public var version: String
  public init(name: String, title: String, version: String) {
    self.name = name
    self.title = title
    self.version = version
  }
}

public struct ACPInitialize: Codable, Equatable, Sendable {
  public var protocolVersion: Int
  public var clientCapabilities: ACPClientCapabilities
  public var clientInfo: ACPImplementation
  public init(clientVersion: String, allowWrites: Bool = false) {
    protocolVersion = ACPProtocol.version
    clientCapabilities = .init(
      fs: .init(readTextFile: true, writeTextFile: allowWrites), terminal: false)
    clientInfo = .init(
      name: "iosdev-workbench", title: "iOSDev Workbench", version: clientVersion)
  }
}

public struct ACPEnvironmentVariable: Codable, Equatable, Sendable {
  public var name: String
  public var value: String
  public init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

public struct ACPMCPServer: Codable, Equatable, Sendable {
  public var name: String
  public var command: String
  public var args: [String]
  public var env: [ACPEnvironmentVariable]
  public init(name: String, command: String, args: [String] = [], env: [String: String] = [:]) {
    self.name = name
    self.command = command
    self.args = args
    self.env = env.keys.sorted().map { .init(name: $0, value: env[$0] ?? "") }
  }
}

public struct ACPNewSession: Codable, Equatable, Sendable {
  public var cwd: String
  public var mcpServers: [ACPMCPServer]
  public init(cwd: URL, mcpServers: [ACPMCPServer]) {
    self.cwd = cwd.path
    self.mcpServers = mcpServers
  }
}

/// A session-level selector exposed by an ACP agent, such as its model or
/// reasoning/thought level. The protocol deliberately keeps these options
/// agent-defined so clients can support every CLI without hard-coded adapters.
public struct ACPConfigOptionValue: Codable, Equatable, Identifiable, Sendable {
  public var value: String
  public var name: String
  public var description: String?

  public var id: String { value }

  public init(value: String, name: String, description: String? = nil) {
    self.value = value
    self.name = name
    self.description = description
  }
}

public struct ACPConfigOption: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var description: String?
  public var category: String?
  public var type: String
  public var currentValue: JSONValue?
  public var options: [ACPConfigOptionValue]

  public init(
    id: String, name: String, description: String? = nil, category: String? = nil,
    type: String = "select", currentValue: JSONValue? = nil,
    options: [ACPConfigOptionValue] = []
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.category = category
    self.type = type
    self.currentValue = currentValue
    self.options = options
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    category = try container.decodeIfPresent(String.self, forKey: .category)
    type = try container.decodeIfPresent(String.self, forKey: .type) ?? "select"
    currentValue = try container.decodeIfPresent(JSONValue.self, forKey: .currentValue)
    options = try container.decodeIfPresent([ACPConfigOptionValue].self, forKey: .options) ?? []
  }
}

public struct ACPContentBlock: Codable, Equatable, Sendable {
  public var type: String
  public var text: String
  public init(text: String) {
    type = "text"
    self.text = text
  }
}

public struct ACPPrompt: Codable, Equatable, Sendable {
  public var sessionId: String
  public var prompt: [ACPContentBlock]
  public init(sessionID: String, text: String) {
    sessionId = sessionID
    prompt = [.init(text: text)]
  }
}

public actor ACPWorkspaceRequestHandler {
  private let policy: ACPPathPolicy
  private let allowWrites: Bool
  private let didMutate: (@Sendable () async -> Void)?

  public init(
    workspace: URL, allowWrites: Bool,
    didMutate: (@Sendable () async -> Void)? = nil
  ) {
    policy = ACPPathPolicy(workspace: workspace)
    self.allowWrites = allowWrites
    self.didMutate = didMutate
  }

  public func handle(_ request: RPCEnvelope) async -> RPCEnvelope {
    do {
      guard let method = request.method, let path = request.params?["path"]?.stringValue else {
        return .init(id: request.id, error: .init(code: -32602, message: "path is required"))
      }
      let url = try policy.resolve(path)
      switch method {
      case "fs/read_text_file":
        let content = try String(contentsOf: url, encoding: .utf8)
        return .init(id: request.id, result: .object(["content": .string(content)]))
      case "fs/write_text_file":
        guard allowWrites else {
          return .init(
            id: request.id,
            error: .init(code: -32062, message: "This ACP session is advisory and read-only"))
        }
        guard let content = request.params?["content"]?.stringValue else {
          return .init(id: request.id, error: .init(code: -32602, message: "content is required"))
        }
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url, options: .atomic)
        await didMutate?()
        return .init(id: request.id, result: .object([:]))
      default:
        return .init(
          id: request.id, error: .init(code: -32601, message: "Unsupported ACP client method"))
      }
    } catch let error as RPCError {
      return .init(id: request.id, error: error)
    } catch {
      return .init(id: request.id, error: .init(code: -32603, message: error.localizedDescription))
    }
  }
}

public enum ACPUpdateKind: String, Codable, Sendable {
  case content, plan, toolCall, permission, mode
  case configOptionUpdate = "config_option_update"
  case authentication, error, completed
}
public struct ACPUpdate: Codable, Sendable {
  public var sessionID: String
  public var kind: ACPUpdateKind
  public var payload: JSONValue
  public var timestamp: Date
  public init(sessionID: String, kind: ACPUpdateKind, payload: JSONValue, timestamp: Date = Date())
  {
    self.sessionID = sessionID
    self.kind = kind
    self.payload = payload
    self.timestamp = timestamp
  }
}

public struct AdapterLockEntry: Codable, Identifiable, Sendable {
  public var id: String
  public var displayName: String
  public var executableNames: [String]
  public var cliExecutableNames: [String]
  public var configurationPaths: [String]
  public var version: String
  public var source: String
  public var sha256: String
  public var license: String
  public var minimumCLIVersion: String?
  public var launchArguments: [String]
  public var supportedACPVersion: Int
}

public enum AdapterAvailability: String, Codable, Sendable {
  case ready
  case cliDetected
  case configurationOnly
  case missing
}

public struct DetectedAdapter: Codable, Identifiable, Sendable {
  public var id: String
  public var displayName: String
  public var executable: URL?
  public var cliExecutable: URL?
  public var configurationDetected: Bool
  public var launchArguments: [String]
  public var mode: String
  public var limitation: String?
  public var availability: AdapterAvailability
}

public enum AdapterManager {
  public static let pinned: [AdapterLockEntry] = [
    .init(
      id: "codex", displayName: "Codex", executableNames: ["codex-acp"],
      cliExecutableNames: ["codex"], configurationPaths: [".codex"], version: "1.1.14",
      source: "@agentclientprotocol/codex-acp@1.1.14",
      sha256: "release-manifest-required", license: "Apache-2.0", minimumCLIVersion: nil,
      launchArguments: [], supportedACPVersion: 1),
    .init(
      id: "claude", displayName: "Claude", executableNames: ["claude-agent-acp"],
      cliExecutableNames: ["claude"], configurationPaths: [".claude"], version: "0.66.0",
      source: "@agentclientprotocol/claude-agent-acp@0.66.0",
      sha256: "release-manifest-required", license: "Proprietary", minimumCLIVersion: nil,
      launchArguments: [], supportedACPVersion: 1),
    .init(
      id: "opencode", displayName: "OpenCode", executableNames: ["opencode"],
      cliExecutableNames: ["opencode"], configurationPaths: [".config/opencode"],
      version: "host-installed", source: "OpenCode", sha256: "host-installed", license: "MIT",
      minimumCLIVersion: nil, launchArguments: ["acp"], supportedACPVersion: 1),
    .init(
      id: "pi", displayName: "Pi", executableNames: ["pi-acp"],
      cliExecutableNames: ["pi"], configurationPaths: [".pi"], version: "0.0.33",
      source: "pi-acp@0.0.33", sha256: "release-manifest-required", license: "MIT",
      minimumCLIVersion: nil, launchArguments: [], supportedACPVersion: 1),
  ]

  public static func detect(
    path: String = ProcessInfo.processInfo.environment["PATH"]
      ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin",
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    managedRoot: URL? = nil
  ) -> [DetectedAdapter] {
    var directories = path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    let conventional = [
      homeDirectory.appending(path: ".local/bin").path,
      homeDirectory.appending(path: ".bun/bin").path,
      homeDirectory.appending(path: ".volta/bin").path,
      homeDirectory.appending(path: "Library/pnpm").path,
      "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
      "/Applications/ChatGPT.app/Contents/Resources",
    ]
    directories.append(contentsOf: conventional)
    var seen: Set<String> = []
    directories = directories.filter { seen.insert($0).inserted }
    return pinned.map { entry in
      var adapterDirectories = directories
      if let managedRoot {
        adapterDirectories.insert(
          managedRoot.appending(path: entry.id).appending(path: entry.version)
            .appending(path: "node_modules/.bin").path,
          at: 0)
      }
      let executable = findExecutable(entry.executableNames, in: adapterDirectories)
      let cliExecutable = findExecutable(entry.cliExecutableNames, in: directories)
      let configurationDetected = entry.configurationPaths.contains {
        FileManager.default.fileExists(atPath: homeDirectory.appending(path: $0).path)
      }
      let structured = executable != nil && entry.supportedACPVersion == ACPProtocol.version
      let availability: AdapterAvailability =
        structured ? .ready
        : cliExecutable != nil ? .cliDetected
        : configurationDetected ? .configurationOnly : .missing
      let limitation: String? = switch availability {
      case .ready: nil
      case .cliDetected: "CLI detected; install the pinned ACP adapter to connect it"
      case .configurationOnly: "Configuration found, but no runnable CLI was detected"
      case .missing: "CLI and ACP adapter were not found on standard executable paths"
      }
      return .init(
        id: entry.id, displayName: entry.displayName, executable: executable,
        cliExecutable: cliExecutable, configurationDetected: configurationDetected,
        launchArguments: entry.launchArguments,
        mode: structured ? "read-write" : "unavailable",
        limitation: limitation, availability: availability)
    }
  }

  private static func findExecutable(_ names: [String], in directories: [String]) -> URL? {
    names.lazy.flatMap { name in
      directories.map { URL(fileURLWithPath: $0).appending(path: name) }
    }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }
}

public final class ACPPathPolicy: Sendable {
  public let workspace: URL
  public init(workspace: URL) { self.workspace = workspace.standardizedFileURL }
  public func resolve(_ clientPath: String) throws -> URL {
    let candidate =
      clientPath.hasPrefix("/")
      ? URL(fileURLWithPath: clientPath).standardizedFileURL
      : workspace.appending(path: clientPath).standardizedFileURL
    guard candidate.path == workspace.path || candidate.path.hasPrefix(workspace.path + "/") else {
      throw RPCError(code: -32060, message: "ACP path is outside the task worktree")
    }
    var current = workspace
    for component in candidate.pathComponents.dropFirst(workspace.pathComponents.count) {
      current.append(path: component)
      if let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey]),
        values.isSymbolicLink == true
      {
        let resolved = current.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(workspace.path + "/") else {
          throw RPCError(code: -32061, message: "ACP path escapes through a symbolic link")
        }
      }
    }
    return candidate
  }
}

public final class ACPClient: @unchecked Sendable {
  private let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
  private let lock = NSLock()
  private var nextID = 1
  private var pending: [RPCID: CheckedContinuation<RPCEnvelope, Error>] = [:]
  private var framer = LineFramer()
  private let onUpdate: @Sendable (RPCEnvelope) -> Void
  private let onRequest: @Sendable (RPCEnvelope) async -> RPCEnvelope
  private let onDiagnostic: @Sendable (String) -> Void

  public init(
    executable: URL, arguments: [String], workspace: URL, environment: [String: String] = [:],
    onUpdate: @escaping @Sendable (RPCEnvelope) -> Void,
    onRequest: @escaping @Sendable (RPCEnvelope) async -> RPCEnvelope = { request in
      .init(
        id: request.id,
        error: .init(code: -32601, message: "The ACP client method is not supported"))
    },
    onDiagnostic: @escaping @Sendable (String) -> Void = { _ in }
  ) throws {
    guard executable.path.hasPrefix("/") else {
      throw ProcessRunnerError.executableMustBeAbsolute(executable.path)
    }
    self.onUpdate = onUpdate
    self.onRequest = onRequest
    self.onDiagnostic = onDiagnostic
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = workspace
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, task in task
    }
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.consume(handle.availableData)
    }
    errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else { return }
      self?.onDiagnostic(message)
    }
    process.terminationHandler = { [weak self] process in
      self?.failPending(
        RPCError(
          code: -32093,
          message: "ACP adapter exited with status \(process.terminationStatus)"))
    }
    try process.run()
  }

  deinit {
    output.fileHandleForReading.readabilityHandler = nil
    errors.fileHandleForReading.readabilityHandler = nil
    process.terminationHandler = nil
    if process.isRunning { process.terminate() }
  }

  public func request(method: String, params: JSONValue? = nil) async throws -> RPCEnvelope {
    let id: RPCID = lock.withLock {
      let value = nextID
      nextID += 1
      return .int(value)
    }
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock { pending[id] = continuation }
      do {
        try send(.init(id: id, method: method, params: params))
      } catch {
        _ = lock.withLock { pending.removeValue(forKey: id) }
        continuation.resume(throwing: error)
      }
    }
  }

  public func notify(method: String, params: JSONValue? = nil) throws {
    try send(.init(method: method, params: params))
  }
  public func cancel() { process.interrupt() }

  private func send(_ envelope: RPCEnvelope) throws {
    let data = try JSONRPCCodec.encodeLine(envelope)
    try lock.withLock { try input.fileHandleForWriting.write(contentsOf: data) }
  }

  private func consume(_ data: Data) {
    guard !data.isEmpty else { return }
    let lines = lock.withLock { framer.append(data) }
    for line in lines {
      guard let envelope = try? JSONRPCCodec.decodeLine(line) else { continue }
      if let id = envelope.id, envelope.method == nil,
        let continuation = lock.withLock({ pending.removeValue(forKey: id) })
      {
        if let error = envelope.error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: envelope)
        }
      } else if envelope.id != nil, envelope.method != nil {
        Task { [weak self] in
          guard let self else { return }
          let response = await self.onRequest(envelope)
          do { try self.send(response) } catch { self.onDiagnostic(error.localizedDescription) }
        }
      } else {
        onUpdate(envelope)
      }
    }
  }

  private func failPending(_ error: Error) {
    let continuations = lock.withLock { () -> [CheckedContinuation<RPCEnvelope, Error>] in
      let values = Array(pending.values)
      pending.removeAll()
      return values
    }
    continuations.forEach { $0.resume(throwing: error) }
  }
}
