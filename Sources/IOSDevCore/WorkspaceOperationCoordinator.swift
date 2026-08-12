import Darwin
import Foundation

public enum WorkspaceOperationKind: String, Codable, Sendable {
  case expoPrebuild
  case cocoaPodsInstall
  case build
  case test
  case projectDiscovery
  case targetDiscovery
  case testDiscovery
}

public enum WorkspaceOperationDiagnostics {
  public static func isBuildDatabaseLock(_ output: String) -> Bool {
    let value = output.lowercased()
    return value.contains("build.db")
      && (value.contains("database is locked") || value.contains("unable to attach db"))
  }
}

public struct WorkspaceOperationBusyError: Error, LocalizedError, Sendable {
  public var requested: WorkspaceOperationKind
  public var ownerDescription: String?

  public init(requested: WorkspaceOperationKind, ownerDescription: String? = nil) {
    self.requested = requested
    self.ownerDescription = ownerDescription
  }

  public var errorDescription: String? {
    let owner = ownerDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
    return owner.flatMap { $0.isEmpty ? nil : $0 }.map {
      "Lys is already running a workspace operation (\($0)). Wait for it to finish before starting \(requested.rawValue)."
    } ?? "Lys is already running a workspace operation. Wait for it to finish before starting \(requested.rawValue)."
  }
}

public final class WorkspaceOperationLease: @unchecked Sendable {
  private let stateLock = NSLock()
  private var descriptor: Int32?

  fileprivate init(descriptor: Int32) { self.descriptor = descriptor }

  public func release() {
    stateLock.withLock {
      guard let descriptor else { return }
      _ = flock(descriptor, LOCK_UN)
      _ = close(descriptor)
      self.descriptor = nil
    }
  }

  deinit { release() }
}

/// Serializes every operation that reads or mutates Xcode's shared workspace state. The advisory
/// lock is process-wide, so the macOS host and its `lysd` child coordinate through the same file.
public actor WorkspaceOperationCoordinator {
  public let workspace: URL
  public let lockURL: URL

  public init(workspace: URL) {
    self.workspace = workspace.standardizedFileURL
    lockURL = workspace.standardizedFileURL.appending(path: ".lys/cache/workspace-operation.lock")
  }

  public func acquire(
    _ kind: WorkspaceOperationKind, wait: Bool = true, timeout: TimeInterval = 15 * 60
  ) async throws -> WorkspaceOperationLease {
    try FileManager.default.createDirectory(
      at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: lockURL.path])
    }
    let deadline = Date().addingTimeInterval(timeout)
    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      if !wait || Date() >= deadline || Task.isCancelled {
        let owner = Self.readOwner(from: descriptor)
        _ = close(descriptor)
        if Task.isCancelled { throw CancellationError() }
        throw WorkspaceOperationBusyError(requested: kind, ownerDescription: owner)
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    Self.writeOwner("\(kind.rawValue) · pid \(getpid())", to: descriptor)
    return WorkspaceOperationLease(descriptor: descriptor)
  }

  private static func readOwner(from descriptor: Int32) -> String? {
    guard lseek(descriptor, 0, SEEK_SET) >= 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: 256)
    let count = read(descriptor, &bytes, bytes.count)
    guard count > 0 else { return nil }
    return String(decoding: bytes.prefix(Int(count)), as: UTF8.self)
  }

  private static func writeOwner(_ owner: String, to descriptor: Int32) {
    _ = ftruncate(descriptor, 0)
    _ = lseek(descriptor, 0, SEEK_SET)
    let data = Data(owner.utf8)
    data.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress else { return }
      _ = write(descriptor, base, bytes.count)
    }
    _ = fsync(descriptor)
  }
}

/// Shares one in-flight result with duplicate callers. This prevents two agent/Run requests from
/// queueing identical builds even before they reach the cross-process workspace lock.
public actor CoalescingOperationRegistry<Key: Hashable & Sendable, Value: Sendable> {
  private var active: [Key: Task<Value, Error>] = [:]

  public init() {}

  public func run(
    key: Key, operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    if let existing = active[key] { return try await existing.value }
    let task = Task { try await operation() }
    active[key] = task
    do {
      let value = try await task.value
      active[key] = nil
      return value
    } catch {
      active[key] = nil
      throw error
    }
  }
}

public struct BuildArtifactDescriptor: Codable, Sendable {
  public var container: String
  public var scheme: String
  public var configuration: String
  public var destination: String
  public var target: AppTarget
  public var builtAt: Date

  public init(
    container: String, scheme: String, configuration: String, destination: String,
    target: AppTarget, builtAt: Date = Date()
  ) {
    self.container = URL(fileURLWithPath: container).standardizedFileURL.path
    self.scheme = scheme
    self.configuration = configuration
    self.destination = destination
    self.target = target
    self.builtAt = builtAt
  }
}

public struct BuildArtifactCache: Sendable {
  public let url: URL

  public init(workspace: URL) {
    url = workspace.standardizedFileURL.appending(path: ".lys/cache/last-successful-build.json")
  }

  public func save(_ descriptor: BuildArtifactDescriptor) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(descriptor).write(to: url, options: .atomic)
  }

  public func load(
    container: String, scheme: String, configuration: String, destination: String
  ) -> AppTarget? {
    guard let data = try? Data(contentsOf: url),
      let descriptor = try? JSONDecoder().decode(BuildArtifactDescriptor.self, from: data),
      descriptor.container == URL(fileURLWithPath: container).standardizedFileURL.path,
      descriptor.scheme == scheme, descriptor.configuration == configuration,
      descriptor.destination == destination, let product = descriptor.target.productPath,
      FileManager.default.fileExists(atPath: product.path)
    else { return nil }
    return descriptor.target
  }
}
