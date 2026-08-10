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
      let manifestURL = worktree.appending(path: ".iosdev-baseline.json")
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
      let manifestURL = activeWorktree.appending(path: ".iosdev-baseline.json")
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
        if path == ".iosdev" || path == ".git" {
          enumerator.skipDescendants()
          continue
        }
        if path == ".iosdev-baseline.json" || path.hasPrefix(".iosdev/")
          || path.hasPrefix(".git/")
          || baseline.ignoredOverlayPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }
          )
          || baseline.submodulePaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
        {
          continue
        }
        if let entry = try fileEntry(at: url, relativePath: path) { current[path] = entry }
      }
    }
    let paths = Set(current.keys).union(baseline.entries.keys)
    return paths.compactMap { path in
      switch (baseline.entries[path], current[path]) {
      case (nil, _?):
        return .init(
          path: path, kind: .added, binary: isBinary(canonicalWorktree.appending(path: path)))
      case (_?, nil): return .init(path: path, kind: .deleted, binary: false)
      case (let before?, let after?) where before != after:
        return .init(
          path: path, kind: .modified, binary: isBinary(canonicalWorktree.appending(path: path)))
      default: return nil
      }
    }.sorted { $0.path < $1.path }
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
  }

  private func overlayCheckoutState(from sourceRoot: URL, to targetRoot: URL) async throws
    -> [String]
  {
    let paths = try await gitNullSeparated([
      "-C", sourceRoot.path, "ls-files", "-z", "--modified", "--deleted", "--others",
      "--exclude-standard",
    ])
    for path in paths {
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
    let snapshotRoot = worktree.appending(path: ".iosdev/baseline", directoryHint: .isDirectory)
    for path in manifest.entries.keys {
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
    let baselineFile = try safeURL(path, under: worktree.appending(path: ".iosdev/baseline"))
    guard FileManager.default.fileExists(atPath: baselineFile.path) else {
      throw WorkspaceError.missingBaseline(path)
    }
    let merge = try await runner.run(
      executable: git,
      arguments: ["merge-file", "-p", current.path, baselineFile.path, source.path])
    guard merge.terminationStatus == 0 || merge.terminationStatus == 1 else {
      return .init(path: path, reason: "git merge-file failed: \(merge.stderr)")
    }
    let artifact = try safeURL(path, under: worktree.appending(path: ".iosdev/conflicts"))
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
