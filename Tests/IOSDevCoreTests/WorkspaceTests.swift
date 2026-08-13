import Foundation
import Testing

@testable import IOSDevCore

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
  try await runGit(["config", "user.email", "fixture@example.com"])
  try await runGit(["config", "user.name", "Fixture"])
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
  try await runGit(["config", "user.email", "fixture@example.com"])
  try await runGit(["config", "user.name", "Fixture"])
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
  try await runGit(["config", "user.email", "fixture@example.com"])
  try await runGit(["config", "user.name", "Fixture"])
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
  try await runGit(["config", "user.email", "fixture@example.com"])
  try await runGit(["config", "user.name", "Fixture"])
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
  #expect(changes.first?.kind == .added)
  #expect(changes[1].kind == .deleted)
  #expect(changes[2].kind == .modified)

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
