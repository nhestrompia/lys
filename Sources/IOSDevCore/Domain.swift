import Foundation

public struct Repository: Codable, Identifiable, Hashable, Sendable {
  public let id: UUID
  public var originalRoot: URL
  public var isGit: Bool
  public var selectedContainer: URL?
  public var preferences: [String: String]
  public init(
    id: UUID = UUID(), originalRoot: URL, isGit: Bool, selectedContainer: URL? = nil,
    preferences: [String: String] = [:]
  ) {
    self.id = id
    self.originalRoot = originalRoot
    self.isGit = isGit
    self.selectedContainer = selectedContainer
    self.preferences = preferences
  }
}

public struct AppTarget: Codable, Identifiable, Hashable, Sendable {
  public var id: String { "\(container.path)#\(scheme)#\(bundleID)" }
  public var container: URL
  public var scheme: String
  public var configuration: String
  public var target: String
  public var bundleID: String
  public var productPath: URL?
  public init(
    container: URL, scheme: String, configuration: String = "Debug", target: String,
    bundleID: String, productPath: URL? = nil
  ) {
    self.container = container
    self.scheme = scheme
    self.configuration = configuration
    self.target = target
    self.bundleID = bundleID
    self.productPath = productPath
  }
}

public struct Destination: Codable, Identifiable, Hashable, Sendable {
  public var id: String { udid }
  public var udid: String
  public var name: String
  public var deviceType: String
  public var runtime: String
  public var state: String
  public var appearance: String?
  public var orientation: String?
  public var locale: String?
  public var contentSizeCategory: String?
  public init(
    udid: String, name: String, deviceType: String, runtime: String, state: String,
    appearance: String? = nil
  ) {
    self.udid = udid
    self.name = name
    self.deviceType = deviceType
    self.runtime = runtime
    self.state = state
    self.appearance = appearance
  }
}

public enum TaskState: String, Codable, CaseIterable, Sendable {
  case preparing, running, awaitingPermission, verifying, review, applied, discarded, failed,
    cancelled
}

public struct DevelopmentTask: Codable, Identifiable, Sendable {
  public let id: UUID
  public var state: TaskState
  public var worktree: URL
  public var prompt: String
  public var agentID: String
  public var acceptanceCriteria: [String]
  public var mutationGeneration: Int
  public var createdAt: Date
  public var updatedAt: Date
  public init(
    id: UUID = UUID(), state: TaskState = .preparing, worktree: URL, prompt: String,
    agentID: String, acceptanceCriteria: [String]
  ) {
    self.id = id
    self.state = state
    self.worktree = worktree
    self.prompt = prompt
    self.agentID = agentID
    self.acceptanceCriteria = acceptanceCriteria
    self.mutationGeneration = 0
    self.createdAt = Date()
    self.updatedAt = Date()
  }
}

public enum EvidenceKind: String, Codable, CaseIterable, Hashable, Sendable {
  case build, test, launch, uiAction, uiAssertion, screenshot, runtimeLog, diff
}

public enum EvidenceStatus: String, Codable, Sendable {
  case passed, failed, blocked, informational
}

public struct Evidence: Codable, Identifiable, Hashable, Sendable {
  public let id: UUID
  public var kind: EvidenceKind
  public var status: EvidenceStatus
  public var taskGeneration: Int
  public var criterionID: String?
  public var destinationUDID: String?
  public var createdAt: Date
  public var artifactPaths: [String]
  public var diagnosticSummary: String
  public var deterministic: Bool
  public var acknowledged: Bool
  public init(
    id: UUID = UUID(), kind: EvidenceKind, status: EvidenceStatus, taskGeneration: Int,
    criterionID: String? = nil, destinationUDID: String? = nil, artifactPaths: [String] = [],
    diagnosticSummary: String = "", deterministic: Bool = true, acknowledged: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.status = status
    self.taskGeneration = taskGeneration
    self.criterionID = criterionID
    self.destinationUDID = destinationUDID
    self.createdAt = Date()
    self.artifactPaths = artifactPaths
    self.diagnosticSummary = diagnosticSummary
    self.deterministic = deterministic
    self.acknowledged = acknowledged
  }
}

public struct ToolResult<T: Codable & Sendable>: Codable, Sendable {
  public var ok: Bool
  public var data: T?
  public var errorCode: String?
  public var message: String
  public var evidenceIDs: [UUID]
  public var diagnostics: [String]
  public var retryable: Bool
  public init(
    ok: Bool, data: T? = nil, errorCode: String? = nil, message: String = "",
    evidenceIDs: [UUID] = [], diagnostics: [String] = [], retryable: Bool = false
  ) {
    self.ok = ok
    self.data = data
    self.errorCode = errorCode
    self.message = message
    self.evidenceIDs = evidenceIDs
    self.diagnostics = diagnostics
    self.retryable = retryable
  }
}

public struct EmptyResult: Codable, Sendable { public init() {} }
