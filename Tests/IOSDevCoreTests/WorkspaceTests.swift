import Foundation
import Testing

@testable import IOSDevCore

/// Fixture repositories must not inherit developer-level git configuration. A global
/// `core.excludesFile` listing a fixture filename hides it from `git add` and `git status`,
/// and global attribute or end-of-line settings rewrite the content these tests diff. The
/// settings are repository-local so every git process touching the fixture observes them,
/// including the ones `WorkspaceManager` spawns with its own inherited environment.
private let fixtureGitSettings = [
  ["user.email", "fixture@example.com"],
  ["user.name", "Fixture"],
  ["core.excludesFile", "/dev/null"],
  ["core.attributesFile", "/dev/null"],
  ["core.autocrlf", "false"],
]

@Test func taskWorktreeOverlaysDirtyCheckoutAndBlocksConflictingApply() async throws {
  let base = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let repository = base.appending(path: "repo")
  let taskRoot = base.appending(path: "tasks")
  try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
  let runner = ProcessRunner()
  let git = URL(fileURLWithPath: "/usr/bin/git")
  func runGit(_ arguments: [String]) async throws {
    let result = try await runner.run(
      executable: git, arguments: ["-C", repository.path] + arguments)
    guard result.succeeded else { throw WorkspaceError.gitFailure(result.stderr) }
  }
  try await runGit(["init"])
  for setting in fixtureGitSettings { try await runGit(["config"] + setting) }
  let tracked = repository.appending(path: "Profile.swift")
  try Data("let theme = \"light\"\n".utf8).write(to: tracked)
  try await runGit(["add", "Profile.swift"])
  try await runGit(["-c", "commit.gpgsign=false", "commit", "-m", "baseline"])
  try Data("let theme = \"developer-dirty\"\n".utf8).write(to: tracked)
  try Data("untracked fixture\n".utf8).write(to: repository.appending(path: "Notes.txt"))

  let manager = WorkspaceManager()
  let prepared = try await manager.createTask(repository: repository, taskRoot: taskRoot)
  #expect(
    try String(contentsOf: prepared.worktree.appending(path: "Profile.swift"), encoding: .utf8)
      .contains("developer-dirty"))
  #expect(
    FileManager.default.fileExists(atPath: prepared.worktree.appending(path: "Notes.txt").path))

  try Data("let theme = \"agent-change\"\n".utf8).write(
    to: prepared.worktree.appending(path: "Profile.swift"))
  try Data("new file\n".utf8).write(to: prepared.worktree.appending(path: "AgentFile.swift"))
  let changes = try await manager.proposedChanges(
    worktree: prepared.worktree, baseline: prepared.manifest)
  #expect(changes.map(\.path).contains("Profile.swift"))
  #expect(changes.map(\.path).contains("AgentFile.swift"))

  try Data("let theme = \"developer-later-change\"\n".utf8).write(to: tracked)
  let report = try await manager.apply(
    paths: ["Profile.swift", "AgentFile.swift"], from: prepared.worktree, to: repository,
    baseline: prepared.manifest)
  #expect(report.conflicts.map(\.path) == ["Profile.swift"])
  #expect(report.applied == ["AgentFile.swift"])
  #expect(try String(contentsOf: tracked, encoding: .utf8).contains("developer-later-change"))
  let conflict = try #require(report.conflicts.first)
  let artifact = try #require(conflict.resolutionArtifact)
  #expect(FileManager.default.fileExists(atPath: artifact))
  #expect(try String(contentsOfFile: artifact, encoding: .utf8).contains("<<<<<<<"))

  let recoverable = try await manager.recoverableTasks(taskRoot: taskRoot)
  #expect(recoverable.map(\.worktree) == [prepared.worktree])
  try await manager.discard(worktree: prepared.worktree, repository: repository, taskRoot: taskRoot)
  #expect(!FileManager.default.fileExists(atPath: prepared.worktree.path))
}

@Test func taskIsolationExcludesAppGeneratedStateFromBaselineAndReview() async throws {
  let base = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let repository = base.appending(path: "repo")
  let taskRoot = base.appending(path: "tasks")
  let generatedFiles = [
    ".iosdev/cache/DerivedData/build.db",
    ".lys/cache/DerivedData/build.db",
    ".lys/artifacts/result.xcresult/data",
  ]
  for path in generatedFiles {
    let url = repository.appending(path: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 7, count: 64 * 1_024).write(to: url)
  }
  try FileManager.default.createDirectory(
    at: repository.appending(path: ".lys"), withIntermediateDirectories: true)
  try Data("project-owned contract\n".utf8)
    .write(to: repository.appending(path: ".lys/contract.json"))

  let runner = ProcessRunner()
  let git = URL(fileURLWithPath: "/usr/bin/git")
  func runGit(_ arguments: [String]) async throws {
    let result = try await runner.run(
      executable: git, arguments: ["-C", repository.path] + arguments)
    guard result.succeeded else { throw WorkspaceError.gitFailure(result.stderr) }
  }
  try await runGit(["init"])
  try await runGit(["config", "user.email", "fixture@example.com"])
  try await runGit(["config", "user.name", "Fixture"])
  try await runGit(["add", "."])
  try await runGit(["-c", "commit.gpgsign=false", "commit", "-m", "baseline"])

  let manager = WorkspaceManager()
  let prepared = try await manager.createTask(repository: repository, taskRoot: taskRoot)
  let generatedManifestPaths = prepared.manifest.entries.keys.filter {
    $0 == ".iosdev" || $0.hasPrefix(".iosdev/") || $0.hasPrefix(".lys/cache/")
      || $0.hasPrefix(".lys/artifacts/")
  }
  #expect(generatedManifestPaths.isEmpty)
  #expect(
    !FileManager.default.fileExists(
      atPath: prepared.worktree.appending(path: ".lys/baseline/.iosdev").path))
  #expect(
    !FileManager.default.fileExists(
      atPath: prepared.worktree.appending(path: ".lys/baseline/.lys/cache").path))

  try Data(repeating: 9, count: 64 * 1_024).write(
    to: prepared.worktree.appending(path: ".iosdev/cache/DerivedData/build.db"))
  try Data(repeating: 9, count: 64 * 1_024).write(
    to: prepared.worktree.appending(path: ".lys/cache/DerivedData/build.db"))
  let buildCache = BuildDerivedDataStore.url(for: prepared.worktree)
  try FileManager.default.createDirectory(at: buildCache, withIntermediateDirectories: true)
  try Data("rebuildable\n".utf8).write(to: buildCache.appending(path: "build.db"))
  #expect(!buildCache.path.contains(prepared.worktree.path))
  let changes = try await manager.proposedChanges(
    worktree: prepared.worktree, baseline: prepared.manifest)
  #expect(changes.isEmpty)

  let report = try await manager.apply(
    paths: [".iosdev/cache/DerivedData/build.db"], from: prepared.worktree, to: repository,
    baseline: prepared.manifest)
  #expect(report.applied.isEmpty)
  #expect(report.conflicts.map(\.path) == [".iosdev/cache/DerivedData/build.db"])

  try await manager.discard(
    worktree: prepared.worktree, repository: repository, taskRoot: taskRoot)
  #expect(!FileManager.default.fileExists(atPath: buildCache.path))
}

@Test func taskReviewPreservesProjectMetadataAndExcludesLysInternals() async throws {
  let base = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let repository = base.appending(path: "repo")
  let taskRoot = base.appending(path: "tasks")
  try FileManager.default.createDirectory(at: repository.appending(path: ".lys"), withIntermediateDirectories: true)
  let runner = ProcessRunner()
  let git = URL(fileURLWithPath: "/usr/bin/git")
  func runGit(_ arguments: [String]) async throws {
    let result = try await runner.run(
      executable: git, arguments: ["-C", repository.path] + arguments)
    guard result.succeeded else { throw WorkspaceError.gitFailure(result.stderr) }
  }
  try await runGit(["init"])
  for setting in fixtureGitSettings { try await runGit(["config"] + setting) }
  try Data("host metadata\n".utf8).write(to: repository.appending(path: ".lys/contract.json"))
  try FileManager.default.createDirectory(
    at: repository.appending(path: "Assets"), withIntermediateDirectories: true)
  try Data([0, 1, 2]).write(to: repository.appending(path: "Assets/icon.png"))
  try Data("let title = \"Before\"\nlet count = 1\n".utf8)
    .write(to: repository.appending(path: "App.swift"))
  try await runGit(["add", "."])
  try await runGit(["-c", "commit.gpgsign=false", "commit", "-m", "baseline"])

  let manager = WorkspaceManager()
  let prepared = try await manager.createTask(repository: repository, taskRoot: taskRoot)
  try FileManager.default.removeItem(at: prepared.worktree.appending(path: ".lys/contract.json"))
  try FileManager.default.removeItem(at: prepared.worktree.appending(path: "Assets/icon.png"))
  try Data("host-private\n".utf8)
    .write(to: prepared.worktree.appending(path: ".lys/baseline/host-private.txt"))
  try FileManager.default.createDirectory(
    at: prepared.worktree.appending(path: ".lys/conflicts"), withIntermediateDirectories: true)
  try Data("conflict-private\n".utf8)
    .write(to: prepared.worktree.appending(path: ".lys/conflicts/manual.txt"))
  try Data("let title = \"After\"\nlet count = 2\n".utf8)
    .write(to: prepared.worktree.appending(path: "App.swift"))

  let changes = try await manager.proposedChanges(
    worktree: prepared.worktree, baseline: prepared.manifest)
  #expect(changes.map(\.path) == [".lys/contract.json", "App.swift", "Assets/icon.png"])
  #expect(changes.last?.binary == true)

  let diff = try await manager.proposedDiff(
    worktree: prepared.worktree, baseline: prepared.manifest,
    change: try #require(changes.first { $0.path == "App.swift" }))
  #expect(diff.addedLineCount == 2)
  #expect(diff.removedLineCount == 2)
  #expect(diff.lines.contains { $0.kind == .removed && $0.text.contains("Before") })
  #expect(diff.lines.contains { $0.kind == .added && $0.text.contains("After") })
}

@Test func taskWorktreeCarriesIgnoredExpoBuildInputsWithoutMakingThemApplyEligible() async throws {
  let base = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let repository = base.appending(path: "repo")
  let taskRoot = base.appending(path: "tasks")
  try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
  let runner = ProcessRunner()
  let git = URL(fileURLWithPath: "/usr/bin/git")
  func runGit(_ arguments: [String]) async throws {
    let result = try await runner.run(
      executable: git, arguments: ["-C", repository.path] + arguments)
    guard result.succeeded else { throw WorkspaceError.gitFailure(result.stderr) }
  }
  try await runGit(["init"])
  for setting in fixtureGitSettings { try await runGit(["config"] + setting) }
  try Data("ios/\nnode_modules/\n".utf8).write(to: repository.appending(path: ".gitignore"))
  try Data("export const value = 1\n".utf8).write(to: repository.appending(path: "index.js"))
  try await runGit(["add", ".gitignore", "index.js"])
  try await runGit(["-c", "commit.gpgsign=false", "commit", "-m", "baseline"])
  try FileManager.default.createDirectory(
    at: repository.appending(path: "ios/App.xcodeproj"), withIntermediateDirectories: true)
  try Data("fixture\n".utf8).write(
    to: repository.appending(path: "ios/App.xcodeproj/project.pbxproj"))
  try FileManager.default.createDirectory(
    at: repository.appending(path: "node_modules/example"), withIntermediateDirectories: true)
  try Data("module.exports = {}\n".utf8).write(
    to: repository.appending(path: "node_modules/example/index.js"))

  let manager = WorkspaceManager()
  let prepared = try await manager.createTask(repository: repository, taskRoot: taskRoot)
  #expect(
    FileManager.default.fileExists(
      atPath: prepared.worktree.appending(path: "ios/App.xcodeproj/project.pbxproj").path))
  let nodeModules = prepared.worktree.appending(path: "node_modules")
  #expect((try nodeModules.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true)
  #expect(Set(prepared.manifest.ignoredOverlayPaths) == ["ios", "node_modules"])

  try Data("generated change\n".utf8).write(
    to: prepared.worktree.appending(path: "ios/App.xcodeproj/project.pbxproj"))
  try Data("export const value = 2\n".utf8).write(
    to: prepared.worktree.appending(path: "index.js"))
  let changes = try await manager.proposedChanges(
    worktree: prepared.worktree, baseline: prepared.manifest)
  #expect(changes.map(\.path) == ["index.js"])

  try await manager.discard(worktree: prepared.worktree, repository: repository, taskRoot: taskRoot)
}

@Test func repositoryReviewReportsWorkingTreeAndBuildsHeadDiff() async throws {
  let base = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let repository = base.appending(path: "repo")
  try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
  let runner = ProcessRunner()
  let git = URL(fileURLWithPath: "/usr/bin/git")
  func runGit(_ arguments: [String]) async throws {
    let result = try await runner.run(
      executable: git, arguments: ["-C", repository.path] + arguments)
    guard result.succeeded else { throw WorkspaceError.gitFailure(result.stderr) }
  }

  try await runGit(["init"])
  for setting in fixtureGitSettings { try await runGit(["config"] + setting) }
  try Data("one\ntwo\n".utf8).write(to: repository.appending(path: "README.md"))
  try Data("remove me\n".utf8).write(to: repository.appending(path: "Deleted.txt"))
  try await runGit(["add", "."])
  try await runGit(["-c", "commit.gpgsign=false", "commit", "-m", "baseline"])

  try Data("one\nchanged\n".utf8).write(to: repository.appending(path: "README.md"))
  try FileManager.default.removeItem(at: repository.appending(path: "Deleted.txt"))
  try FileManager.default.createDirectory(
    at: repository.appending(path: ".lys"), withIntermediateDirectories: true)
  try Data("project-owned contract\n".utf8)
    .write(to: repository.appending(path: ".lys/contract.json"))

  let manager = WorkspaceManager()
  let changes = try await manager.repositoryChanges(repository: repository)
  #expect(changes.map(\.path) == [".lys/contract.json", "Deleted.txt", "README.md"])
  #expect(changes.map(\.kind) == [.added, .deleted, .modified])

  let diff = try await manager.repositoryDiff(
    repository: repository, change: try #require(changes.first { $0.path == "README.md" }))
  #expect(diff.addedLineCount == 1)
  #expect(diff.removedLineCount == 1)
  #expect(diff.lines.contains { $0.kind == .removed && $0.text == "two" })
  #expect(diff.lines.contains { $0.kind == .added && $0.text == "changed" })

  let deletedDiff = try await manager.repositoryDiff(
    repository: repository, change: try #require(changes.first { $0.path == "Deleted.txt" }))
  #expect(deletedDiff.removedLineCount == 1)
  #expect(deletedDiff.addedLineCount == 0)
}
