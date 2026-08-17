import CryptoKit
import Foundation

public struct ManifestEntry: Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Sendable { case file, symlink }
  public var path: String
  public var kind: Kind
  public var mode: UInt16
  public var hash: String
  public var symlinkTarget: String?
}

public struct BaselineManifest: Codable, Sendable {
  public var repositoryRoot: String
  public var revision: String
  public var createdAt: Date
  public var entries: [String: ManifestEntry]
  public var submodulePaths: [String]
  public var ignoredOverlayPaths: [String]
}

public enum ProposedChangeKind: String, Codable, Sendable { case added, modified, deleted }
public struct ProposedChange: Codable, Identifiable, Sendable {
  public var id: String { path }
  public var path: String
  public var kind: ProposedChangeKind
  public var binary: Bool

  public init(path: String, kind: ProposedChangeKind, binary: Bool) {
    self.path = path
    self.kind = kind
    self.binary = binary
  }
}

public enum ProposedDiffLineKind: String, Codable, Sendable, Hashable {
  case context
  case added
  case removed
}

public struct ProposedDiffLine: Codable, Identifiable, Sendable, Hashable {
  public var id: Int
  public var kind: ProposedDiffLineKind
  public var oldLineNumber: Int?
  public var newLineNumber: Int?
  public var text: String

  public init(
    id: Int, kind: ProposedDiffLineKind, oldLineNumber: Int?, newLineNumber: Int?, text: String
  ) {
    self.id = id
    self.kind = kind
    self.oldLineNumber = oldLineNumber
    self.newLineNumber = newLineNumber
    self.text = text
  }
}

public struct ProposedFileDiff: Codable, Sendable {
  public var path: String
  public var kind: ProposedChangeKind
  public var binary: Bool
  public var lines: [ProposedDiffLine]
  public var addedLineCount: Int
  public var removedLineCount: Int
  public var message: String?

  public init(
    path: String,
    kind: ProposedChangeKind,
    binary: Bool,
    lines: [ProposedDiffLine],
    addedLineCount: Int,
    removedLineCount: Int,
    message: String? = nil
  ) {
    self.path = path
    self.kind = kind
    self.binary = binary
    self.lines = lines
    self.addedLineCount = addedLineCount
    self.removedLineCount = removedLineCount
    self.message = message
  }
}

public struct ApplyConflict: Codable, Identifiable, Sendable {
  public var id: String { path }
  public var path: String
  public var reason: String
  public var resolutionArtifact: String?

  public init(path: String, reason: String, resolutionArtifact: String? = nil) {
    self.path = path
    self.reason = reason
    self.resolutionArtifact = resolutionArtifact
  }
}
public struct ApplyReport: Codable, Sendable {
  public var applied: [String]
  public var conflicts: [ApplyConflict]
}

public struct RecoverableWorkspace: Identifiable, Sendable {
  public var id: String { worktree.path }
  public var worktree: URL
  public var manifest: BaselineManifest
}

public enum WorkspaceError: Error, LocalizedError {
  case notGitRepository
  case unsafePath(String)
  case gitFailure(String)
  case missingBaseline(String)
  public var errorDescription: String? {
    switch self {
    case .notGitRepository: "Editable tasks require a Git repository"
    case .unsafePath(let path): "Unsafe workspace path: \(path)"
    case .gitFailure(let message): "Git operation failed: \(message)"
    case .missingBaseline(let path): "No baseline exists for \(path)"
    }
  }
}

public actor WorkspaceManager {
  private let git = URL(fileURLWithPath: "/usr/bin/git")
  private let runner = ProcessRunner()
  public init() {}

  public func recoverableTasks(taskRoot: URL) throws -> [RecoverableWorkspace] {
    guard FileManager.default.fileExists(atPath: taskRoot.path) else { return [] }
    let directories = try FileManager.default.contentsOfDirectory(
      at: taskRoot, includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return directories.compactMap { worktree in
      let manifestURL = worktree.appending(path: ".lys-baseline.json")
      guard let data = try? Data(contentsOf: manifestURL),
        let manifest = try? decoder.decode(BaselineManifest.self, from: data),
        FileManager.default.fileExists(atPath: manifest.repositoryRoot),
        worktree.standardizedFileURL.path.hasPrefix(taskRoot.standardizedFileURL.path + "/")
      else { return nil }
      return .init(worktree: worktree.standardizedFileURL, manifest: manifest)
    }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
  }

  public func createTask(repository: URL, taskRoot: URL, taskID: UUID = UUID()) async throws -> (
    worktree: URL, manifest: BaselineManifest
  ) {
    let check = try await runner.run(
      executable: git, arguments: ["-C", repository.path, "rev-parse", "--show-toplevel"])
    guard check.succeeded else { throw WorkspaceError.notGitRepository }
    let canonical = URL(
      fileURLWithPath: check.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    ).standardizedFileURL
    let worktree = taskRoot.appending(path: taskID.uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: taskRoot, withIntermediateDirectories: true)
    guard worktree.standardizedFileURL.path.hasPrefix(taskRoot.standardizedFileURL.path + "/")
    else { throw WorkspaceError.unsafePath(worktree.path) }
    let revision = try await gitOutput(["-C", canonical.path, "rev-parse", "HEAD"])
    let add = try await runner.run(
      executable: git,
      arguments: ["-C", canonical.path, "worktree", "add", "--detach", worktree.path, revision])
    guard add.succeeded else { throw WorkspaceError.gitFailure(add.stderr) }
    do {
      let activeWorktree = worktree.resolvingSymlinksInPath().standardizedFileURL
      let ignoredOverlayPaths = try await overlayCheckoutState(from: canonical, to: activeWorktree)
      let manifest = try await makeManifest(
        root: canonical, revision: revision, ignoredOverlayPaths: ignoredOverlayPaths)
      try snapshotBaseline(manifest, from: canonical, into: activeWorktree)
      let manifestURL = activeWorktree.appending(path: ".lys-baseline.json")
      let data = try JSONEncoder.pretty.encode(manifest)
      try data.write(to: manifestURL, options: .atomic)
      return (activeWorktree, manifest)
    } catch {
      _ = try? await runner.run(
        executable: git,
        arguments: ["-C", canonical.path, "worktree", "remove", "--force", worktree.path])
      throw error
    }
  }

  public func makeManifest(
    root: URL, revision: String, ignoredOverlayPaths: [String] = []
  ) async throws -> BaselineManifest {
    let paths = try await gitNullSeparated([
      "-C", root.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard",
    ])
    var entries: [String: ManifestEntry] = [:]
    for path in paths {
      guard !isGeneratedWorkspacePath(path) else { continue }
      let url = try safeURL(path, under: root)
      if let entry = try fileEntry(at: url, relativePath: path) { entries[path] = entry }
    }
    let submoduleOutput = try await gitOutput([
      "-C", root.path, "submodule", "status", "--recursive",
    ])
    let submodulePaths = submoduleOutput.split(separator: "\n").compactMap { line -> String? in
      let fields = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
      return fields.count > 1 ? String(fields[1]) : nil
    }
    return .init(
      repositoryRoot: root.path, revision: revision.trimmingCharacters(in: .whitespacesAndNewlines),
      createdAt: Date(), entries: entries, submodulePaths: submodulePaths,
      ignoredOverlayPaths: ignoredOverlayPaths)
  }

  public func proposedChanges(worktree: URL, baseline: BaselineManifest) throws -> [ProposedChange]
  {
    var current: [String: ManifestEntry] = [:]
    let canonicalWorktree = worktree.resolvingSymlinksInPath().standardizedFileURL
    if let enumerator = FileManager.default.enumerator(
      at: canonicalWorktree, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: [])
    {
      while let url = enumerator.nextObject() as? URL {
        let path = url.standardizedFileURL.pathComponents.dropFirst(
          canonicalWorktree.pathComponents.count
        ).joined(separator: "/")
        if path == ".git" || isGeneratedWorkspaceRoot(path) {
          enumerator.skipDescendants()
          continue
        }
        if isReviewExcludedPath(path, baseline: baseline) {
          continue
        }
        if let entry = try fileEntry(at: url, relativePath: path) { current[path] = entry }
      }
    }
    let baselinePaths = baseline.entries.keys.filter {
      !isReviewExcludedPath($0, baseline: baseline)
    }
    let paths = Set(current.keys).union(baselinePaths)
    let baselineRoot = canonicalWorktree.appending(path: ".lys/baseline", directoryHint: .isDirectory)
    return paths.compactMap { path in
      switch (baseline.entries[path], current[path]) {
      case (nil, _?):
        return .init(
          path: path, kind: .added, binary: isBinary(at: path, under: canonicalWorktree))
      case (_?, nil):
        return .init(path: path, kind: .deleted, binary: isBinary(at: path, under: baselineRoot))
      case (let before?, let after?) where before != after:
        return .init(
          path: path, kind: .modified, binary: isBinary(at: path, under: canonicalWorktree))
      default: return nil
      }
    }.sorted { $0.path < $1.path }
  }

  public func repositoryChanges(repository: URL) async throws -> [ProposedChange] {
    let result = try await runner.run(
      executable: git,
      arguments: [
        "-C", repository.path, "status", "--porcelain=v1", "--untracked-files=all", "-z",
      ])
    guard result.succeeded else { throw WorkspaceError.gitFailure(result.stderr) }

    let records = result.stdout.split(separator: "\0", omittingEmptySubsequences: true)
      .map(String.init)
    var changes: [ProposedChange] = []
    var index = 0
    while index < records.count {
      let record = records[index]
      index += 1
      guard record.count >= 3 else { continue }
      let status = String(record.prefix(2))
      let path = String(record.dropFirst(3))
      guard !path.isEmpty else { continue }

      let kind = repositoryChangeKind(status)
      let binary: Bool
      if kind == .deleted {
        binary = try await repositoryBlobIsBinary(repository: repository, path: path)
      } else {
        binary = isBinary(at: path, under: repository)
      }
      changes.append(.init(path: path, kind: kind, binary: binary))

      // -z emits a second pathname for rename/copy records. The new path is the first
      // pathname in the porcelain-v1 form; the old path is only consumed here.
      if status.first == "R" || status.first == "C", index < records.count { index += 1 }
    }
    return changes.sorted { $0.path < $1.path }
  }

  public func proposedDiff(
    worktree: URL, baseline: BaselineManifest, change: ProposedChange
  ) throws -> ProposedFileDiff {
    let baselineRoot = worktree.appending(path: ".lys/baseline", directoryHint: .isDirectory)
    let before = try safeURL(change.path, under: baselineRoot)
    let after = try safeURL(change.path, under: worktree)
    return makeFileDiff(
      path: change.path, kind: change.kind, binaryHint: change.binary,
      beforeData: try dataIfPresent(at: before), afterData: try dataIfPresent(at: after))
  }

  public func repositoryDiff(
    repository: URL, change: ProposedChange
  ) async throws -> ProposedFileDiff {
    let after = try safeURL(change.path, under: repository)
    let afterData = try dataIfPresent(at: after)
    if change.kind == .added {
      return makeFileDiff(
        path: change.path, kind: change.kind, binaryHint: change.binary,
        beforeData: nil, afterData: afterData)
    }
    let binary: Bool
    if change.binary {
      binary = true
    } else {
      binary = try await repositoryBlobIsBinary(repository: repository, path: change.path)
    }
    let beforeData = binary ? nil : try await repositoryBlobData(
      repository: repository, path: change.path)
    return makeFileDiff(
      path: change.path, kind: change.kind, binaryHint: binary,
      beforeData: beforeData, afterData: afterData)
  }

  public func apply(
    paths: [String], from worktree: URL, to original: URL, baseline: BaselineManifest
  ) async throws -> ApplyReport {
    var report = ApplyReport(applied: [], conflicts: [])
    for path in paths {
      guard !path.hasPrefix("../"), !path.contains("/../"), path != ".git" else {
        report.conflicts.append(.init(path: path, reason: "Unsafe path"))
        continue
      }
      if isGeneratedWorkspacePath(path) {
        report.conflicts.append(
          .init(path: path, reason: "App-generated workspace data cannot be applied"))
        continue
      }
      if baseline.submodulePaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
        report.conflicts.append(
          .init(
            path: path,
            reason:
              "This path belongs to a submodule. Open that submodule as its own repository before applying edits."
          ))
        continue
      }
      let source = try safeURL(path, under: worktree)
      let destination = try safeURL(path, under: original)
      let base = baseline.entries[path]
      let current = try fileEntry(at: destination, relativePath: path)
      if current != base {
        report.conflicts.append(
          try await prepareMergeConflict(
            path: path, worktree: worktree, source: source, current: destination, base: base)
        )
        continue
      }
      if FileManager.default.fileExists(atPath: source.path) {
        try FileManager.default.createDirectory(
          at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
      } else if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      report.applied.append(path)
    }
    return report
  }

  public func discard(worktree: URL, repository: URL, taskRoot: URL) async throws {
    let safeRoot = taskRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
    guard worktree.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(safeRoot) else {
      throw WorkspaceError.unsafePath(worktree.path)
    }
    let outcome = try await runner.run(
      executable: git,
      arguments: ["-C", repository.path, "worktree", "remove", "--force", worktree.path])
    guard outcome.succeeded else { throw WorkspaceError.gitFailure(outcome.stderr) }
    try? BuildDerivedDataStore.remove(for: worktree)
  }

  private func repositoryBlobData(repository: URL, path: String) async throws -> Data? {
    let result = try await runner.run(
      executable: git,
      arguments: ["-C", repository.path, "show", "HEAD:\(path)"],
      maximumOutputBytes: 2_000_000)
    guard result.succeeded else { return nil }
    return Data(result.stdout.utf8)
  }

  private func repositoryBlobIsBinary(repository: URL, path: String) async throws -> Bool {
    let result = try await runner.run(
      executable: git,
      arguments: ["-C", repository.path, "diff", "--numstat", "HEAD", "--", path],
      maximumOutputBytes: 64 * 1_024)
    guard result.succeeded else { throw WorkspaceError.gitFailure(result.stderr) }
    return result.stdout.split(separator: "\n").contains { line in
      line.hasPrefix("-\t-\t")
    }
  }

  private func overlayCheckoutState(from sourceRoot: URL, to targetRoot: URL) async throws
    -> [String]
  {
    let paths = try await gitNullSeparated([
      "-C", sourceRoot.path, "ls-files", "-z", "--modified", "--deleted", "--others",
      "--exclude-standard",
    ])
    for path in paths {
      if isGeneratedWorkspacePath(path) { continue }
      let source = try safeURL(path, under: sourceRoot)
      let target = try safeURL(path, under: targetRoot)
      if FileManager.default.fileExists(atPath: source.path) {
        try FileManager.default.createDirectory(
          at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: source, to: target)
      } else if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
    }
    var ignoredOverlayPaths: [String] = []
    let copiedDependencies = ["Pods", ".build", "Carthage/Build", "ios"]
    for path in copiedDependencies {
      let source = try safeURL(path, under: sourceRoot)
      var directory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: source.path, isDirectory: &directory),
        directory.boolValue
      else { continue }
      let ignored = try await runner.run(
        executable: git, arguments: ["-C", sourceRoot.path, "check-ignore", "-q", path])
      guard ignored.succeeded else { continue }
      let target = try safeURL(path, under: targetRoot)
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: source, to: target)
      ignoredOverlayPaths.append(path)
    }
    // JavaScript dependency trees can contain hundreds of thousands of files. Treat the
    // original checkout's ignored node_modules as a shared, read-only dependency cache rather
    // than making every task pay for a recursive copy. It is excluded from review/apply and the
    // ACP filesystem policy rejects traversal through this link outside the task worktree.
    let nodeModules = "node_modules"
    let source = try safeURL(nodeModules, under: sourceRoot)
    var directory: ObjCBool = false
    if FileManager.default.fileExists(atPath: source.path, isDirectory: &directory),
      directory.boolValue
    {
      let ignored = try await runner.run(
        executable: git, arguments: ["-C", sourceRoot.path, "check-ignore", "-q", nodeModules])
      if ignored.succeeded {
        let target = try safeURL(nodeModules, under: targetRoot)
        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
        ignoredOverlayPaths.append(nodeModules)
      }
    }
    return ignoredOverlayPaths
  }

  private func snapshotBaseline(
    _ manifest: BaselineManifest, from original: URL, into worktree: URL
  )
    throws
  {
    let snapshotRoot = worktree.appending(path: ".lys/baseline", directoryHint: .isDirectory)
    for path in manifest.entries.keys {
      if isGeneratedWorkspacePath(path) { continue }
      let source = try safeURL(path, under: original)
      guard FileManager.default.fileExists(atPath: source.path) else { continue }
      let destination = try safeURL(path, under: snapshotRoot)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: source, to: destination)
    }
  }

  private func prepareMergeConflict(
    path: String, worktree: URL, source: URL, current: URL, base: ManifestEntry?
  ) async throws -> ApplyConflict {
    guard let base, base.kind == .file,
      FileManager.default.fileExists(atPath: source.path),
      FileManager.default.fileExists(atPath: current.path), !isBinary(source), !isBinary(current)
    else {
      return .init(
        path: path,
        reason:
          "The original checkout changed and this deletion, addition, symlink, or binary change cannot be merged automatically."
      )
    }
    let baselineFile = try safeURL(path, under: worktree.appending(path: ".lys/baseline"))
    guard FileManager.default.fileExists(atPath: baselineFile.path) else {
      throw WorkspaceError.missingBaseline(path)
    }
    let merge = try await runner.run(
      executable: git,
      arguments: ["merge-file", "-p", current.path, baselineFile.path, source.path])
    guard merge.terminationStatus == 0 || merge.terminationStatus == 1 else {
      return .init(path: path, reason: "git merge-file failed: \(merge.stderr)")
    }
    let artifact = try safeURL(path, under: worktree.appending(path: ".lys/conflicts"))
    try FileManager.default.createDirectory(
      at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(merge.stdout.utf8).write(to: artifact, options: .atomic)
    return .init(
      path: path,
      reason:
        merge.terminationStatus == 0
        ? "A clean three-way merge was prepared for manual review; the original was not overwritten."
        : "A three-way merge with conflict markers was prepared for manual resolution; the original was not overwritten.",
      resolutionArtifact: artifact.path)
  }

  private func gitOutput(_ arguments: [String]) async throws -> String {
    let result = try await runner.run(executable: git, arguments: arguments)
    guard result.succeeded else { throw WorkspaceError.gitFailure(result.stderr) }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func gitNullSeparated(_ arguments: [String]) async throws -> [String] {
    let result = try await runner.run(executable: git, arguments: arguments)
    guard result.succeeded else { throw WorkspaceError.gitFailure(result.stderr) }
    return result.stdout.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
  }
}

private func repositoryChangeKind(_ status: String) -> ProposedChangeKind {
  if status == "??" || status.contains("A") { return .added }
  if status.contains("D") { return .deleted }
  return .modified
}

private func makeFileDiff(
  path: String,
  kind: ProposedChangeKind,
  binaryHint: Bool,
  beforeData: Data?,
  afterData: Data?
) -> ProposedFileDiff {
  let binary = binaryHint || (beforeData.map(isBinaryData) ?? false)
    || (afterData.map(isBinaryData) ?? false)

  if binary {
    return .init(
      path: path, kind: kind, binary: true, lines: [], addedLineCount: 0,
      removedLineCount: 0, message: "Binary file · line diff unavailable")
  }

  let maxBytes = 1_000_000
  if (beforeData?.count ?? 0) > maxBytes || (afterData?.count ?? 0) > maxBytes {
    return .init(
      path: path, kind: kind, binary: false, lines: [], addedLineCount: 0,
      removedLineCount: 0, message: "Diff unavailable for files larger than 1 MB")
  }

  guard beforeData == nil || beforeData.flatMap({ String(data: $0, encoding: .utf8) }) != nil,
    afterData == nil || afterData.flatMap({ String(data: $0, encoding: .utf8) }) != nil
  else {
    return .init(
      path: path, kind: kind, binary: true, lines: [], addedLineCount: 0,
      removedLineCount: 0, message: "Text preview unavailable for this file")
  }

  let beforeText = beforeData.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
  let afterText = afterData.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
  let lines = makeDiffLines(before: splitLines(beforeText), after: splitLines(afterText))
  let added = lines.reduce(into: 0) { count, line in
    if line.kind == .added { count += 1 }
  }
  let removed = lines.reduce(into: 0) { count, line in
    if line.kind == .removed { count += 1 }
  }
  return .init(
    path: path, kind: kind, binary: false, lines: lines,
    addedLineCount: added, removedLineCount: removed,
    message: lines.isEmpty ? "No text lines to display" : nil)
}

private func isReviewExcludedPath(_ path: String, baseline: BaselineManifest) -> Bool {
  isGeneratedWorkspacePath(path) || path == ".git" || path.hasPrefix(".git/")
    || baseline.ignoredOverlayPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
    || baseline.submodulePaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
}

private let generatedWorkspaceRoots = [
  ".iosdev", // Legacy app-owned task state.
  ".lys/artifacts",
  ".lys/cache",
  ".lys/baseline",
  ".lys/conflicts",
]

private let generatedWorkspaceFiles = [
  ".iosdev-baseline.json", // Legacy app-owned task metadata.
  ".lys-baseline.json",
]

private func isGeneratedWorkspaceRoot(_ path: String) -> Bool {
  generatedWorkspaceRoots.contains(path)
}

private func isGeneratedWorkspacePath(_ path: String) -> Bool {
  generatedWorkspaceFiles.contains(path)
    || generatedWorkspaceRoots.contains { root in
      path == root || path.hasPrefix(root + "/")
    }
}

private func dataIfPresent(at url: URL) throws -> Data? {
  guard FileManager.default.fileExists(atPath: url.path) else { return nil }
  return try Data(contentsOf: url, options: .mappedIfSafe)
}

private func isBinaryData(_ data: Data) -> Bool {
  data.prefix(8_192).contains(0)
}

private func isBinary(at path: String, under root: URL) -> Bool {
  guard let url = try? safeURL(path, under: root) else { return false }
  return isBinary(url)
}

private func splitLines(_ text: String) -> [String] {
  text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

private func makeDiffLines(before: [String], after: [String]) -> [ProposedDiffLine] {
  let maxCells = 1_500_000
  guard before.count.multipliedReportingOverflow(by: after.count).overflow == false,
    before.count * after.count <= maxCells
  else {
    return fallbackDiffLines(before: before, after: after)
  }

  var lcs = Array(
    repeating: Array(repeating: 0, count: after.count + 1), count: before.count + 1)
  if !before.isEmpty, !after.isEmpty {
    for oldIndex in stride(from: before.count - 1, through: 0, by: -1) {
      for newIndex in stride(from: after.count - 1, through: 0, by: -1) {
        lcs[oldIndex][newIndex] = before[oldIndex] == after[newIndex]
          ? lcs[oldIndex + 1][newIndex + 1] + 1
          : max(lcs[oldIndex + 1][newIndex], lcs[oldIndex][newIndex + 1])
      }
    }
  }

  var oldIndex = 0
  var newIndex = 0
  var lines: [ProposedDiffLine] = []
  while oldIndex < before.count || newIndex < after.count {
    if oldIndex < before.count, newIndex < after.count, before[oldIndex] == after[newIndex] {
      lines.append(
        .init(
          id: lines.count, kind: .context, oldLineNumber: oldIndex + 1,
          newLineNumber: newIndex + 1, text: before[oldIndex]))
      oldIndex += 1
      newIndex += 1
    } else if newIndex == after.count
      || (oldIndex < before.count && lcs[oldIndex + 1][newIndex] >= lcs[oldIndex][newIndex + 1])
    {
      lines.append(
        .init(
          id: lines.count, kind: .removed, oldLineNumber: oldIndex + 1, newLineNumber: nil,
          text: before[oldIndex]))
      oldIndex += 1
    } else {
      lines.append(
        .init(
          id: lines.count, kind: .added, oldLineNumber: nil, newLineNumber: newIndex + 1,
          text: after[newIndex]))
      newIndex += 1
    }
  }
  return lines
}

private func fallbackDiffLines(before: [String], after: [String]) -> [ProposedDiffLine] {
  var lines: [ProposedDiffLine] = []
  for (index, text) in before.enumerated() {
    lines.append(
      .init(id: lines.count, kind: .removed, oldLineNumber: index + 1, newLineNumber: nil, text: text))
  }
  for (index, text) in after.enumerated() {
    lines.append(
      .init(id: lines.count, kind: .added, oldLineNumber: nil, newLineNumber: index + 1, text: text))
  }
  return lines
}

private func safeURL(_ path: String, under root: URL) throws -> URL {
  guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
    throw WorkspaceError.unsafePath(path)
  }
  let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
  let resolved = canonicalRoot.appending(path: path).standardizedFileURL
  guard resolved.path == canonicalRoot.path || resolved.path.hasPrefix(canonicalRoot.path + "/")
  else { throw WorkspaceError.unsafePath(path) }
  return resolved
}

private func fileEntry(at url: URL, relativePath: String) throws -> ManifestEntry? {
  let manager = FileManager.default
  guard manager.fileExists(atPath: url.path) else { return nil }
  let attributes = try manager.attributesOfItem(atPath: url.path)
  let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
  if (attributes[.type] as? FileAttributeType) == .typeSymbolicLink {
    let target = try manager.destinationOfSymbolicLink(atPath: url.path)
    return .init(
      path: relativePath, kind: .symlink, mode: mode, hash: sha256(Data(target.utf8)),
      symlinkTarget: target)
  }
  guard (attributes[.type] as? FileAttributeType) == .typeRegular else { return nil }
  return .init(
    path: relativePath, kind: .file, mode: mode, hash: sha256(try Data(contentsOf: url)),
    symlinkTarget: nil)
}

private func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
private func isBinary(_ url: URL) -> Bool {
  (try? Data(contentsOf: url, options: .mappedIfSafe).prefix(8_192).contains(0)) ?? false
}

extension JSONEncoder {
  fileprivate static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}
