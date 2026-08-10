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
