import Foundation
import Testing

@testable import IOSDevCore

private actor OperationInvocationCounter {
  private var value = 0

  func perform() async throws -> Int {
    value += 1
    try await Task.sleep(for: .milliseconds(150))
    return 73
  }

  func count() -> Int { value }
}

@Test func runAndAgentBuildRequestsShareOneInFlightOperation() async throws {
  let registry = CoalescingOperationRegistry<String, Int>()
  let counter = OperationInvocationCounter()

  async let runButton = registry.run(key: "same-build") { try await counter.perform() }
  async let agentFlow = registry.run(key: "same-build") { try await counter.perform() }

  #expect(try await runButton == 73)
  #expect(try await agentFlow == 73)
  #expect(await counter.count() == 1)
}

@Test func expoPreparationIsBlockedWhileBuildOwnsWorkspace() async throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "lys-operation-tests-\(UUID().uuidString)")
  let buildCoordinator = WorkspaceOperationCoordinator(workspace: root)
  let expoCoordinator = WorkspaceOperationCoordinator(workspace: root)
  let build = try await buildCoordinator.acquire(.build)
  defer { build.release() }

  do {
    _ = try await expoCoordinator.acquire(.expoPrebuild, wait: false)
    Issue.record("Expo preparation acquired a workspace already owned by a build")
  } catch let error as WorkspaceOperationBusyError {
    #expect(error.requested == .expoPrebuild)
    #expect(error.ownerDescription?.contains("build") == true)
  }
}

@Test func successfulBuildArtifactSurvivesRuntimeRestart() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "lys-artifact-tests-\(UUID().uuidString)")
  let container = root.appending(path: "Demo.xcworkspace")
  let product = root.appending(path: "DerivedData/Build/Demo.app")
  try FileManager.default.createDirectory(at: product, withIntermediateDirectories: true)
  let target = AppTarget(
    container: container, scheme: "Demo", target: "Demo", bundleID: "dev.lys.demo",
    productPath: product)
  let cache = BuildArtifactCache(workspace: root)
  try cache.save(
    .init(
      container: container.path, scheme: "Demo", configuration: "Debug",
      destination: "platform=iOS Simulator,id=SIM", target: target))

  let reloaded = BuildArtifactCache(workspace: root).load(
    container: container.path, scheme: "Demo", configuration: "Debug",
    destination: "platform=iOS Simulator,id=SIM")
  #expect(reloaded?.bundleID == "dev.lys.demo")
  #expect(
    BuildArtifactCache(workspace: root).load(
      container: container.path, scheme: "Other", configuration: "Debug",
      destination: "platform=iOS Simulator,id=SIM") == nil)
}

@Test func buildDatabaseLockIsAHostOrchestrationDiagnostic() {
  #expect(
    WorkspaceOperationDiagnostics.isBuildDatabaseLock(
      "error: unable to attach DB: accessing /tmp/XCBuildData/build.db: database is locked"))
  #expect(!WorkspaceOperationDiagnostics.isBuildDatabaseLock("SwiftCompile failed in App.swift"))
}
