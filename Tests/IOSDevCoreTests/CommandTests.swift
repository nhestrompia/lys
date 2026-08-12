import Foundation
import Testing

@testable import IOSDevCore

@Test func simulatorCommandsPreserveArgumentsWithoutShellInterpolation() {
  let simctl = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl")
  let app = URL(fileURLWithPath: "/tmp/My App; touch nope.app")
  #expect(
    AppleCommandBuilder.bootStatus(simctl: simctl, udid: "DEVICE").arguments == [
      "bootstatus", "DEVICE", "-b",
    ])
  #expect(
    AppleCommandBuilder.install(simctl: simctl, udid: "DEVICE", app: app).arguments == [
      "install", "DEVICE", app.path,
    ])
  #expect(
    AppleCommandBuilder.launch(simctl: simctl, udid: "DEVICE", bundleID: "com.example.app")
      .arguments == ["launch", "DEVICE", "com.example.app"])
  #expect(
    AppleCommandBuilder.launch(
      simctl: simctl, udid: "DEVICE", bundleID: "com.example.app",
      arguments: ["-RCT_jsLocation", "127.0.0.1:8081"]
    ).arguments == [
      "launch", "DEVICE", "com.example.app", "-RCT_jsLocation", "127.0.0.1:8081",
    ])
  let authenticated = AppleCommandBuilder.authenticatedLaunch(
    simctl: simctl, udid: "DEVICE", bundleID: "com.example.app",
    developerDirectory: "/Applications/Xcode.app/Contents/Developer",
    values: ["LYS_TEST_SESSION_TOKEN": "protected-value"])
  #expect(authenticated.arguments == ["launch", "DEVICE", "com.example.app", "-LysTesting"])
  #expect(!authenticated.arguments.contains("protected-value"))
  #expect(authenticated.environment["SIMCTL_CHILD_LYS_TEST_SESSION_TOKEN"] == "protected-value")
  #expect(
    AppleCommandBuilder.statusBar(simctl: simctl, udid: "DEVICE", overrides: ["time": "09:41"])
      .arguments == ["status_bar", "DEVICE", "override", "--time", "09:41"])
  #expect(
    AppleCommandBuilder.logQuery(
      simctl: simctl, udid: "DEVICE", process: "App; harmless", seconds: 300
    ).arguments == [
      "spawn", "DEVICE", "log", "show", "--style", "compact", "--last", "300s",
      "--predicate", "process == \"App; harmless\"",
    ])
  let metro = AppleCommandBuilder.configureMetro(
    simctl: simctl, udid: "DEVICE", bundleID: "com.example.app")
  #expect(
    metro[0].arguments == [
      "spawn", "DEVICE", "defaults", "write", "com.example.app", "RCT_jsLocation",
      "127.0.0.1:8081",
    ])
  #expect(
    metro[1].arguments == [
      "spawn", "DEVICE", "defaults", "write", "com.example.app", "RCT_enableDev", "-bool",
      "YES",
    ])

  let axe = URL(fileURLWithPath: "/opt/homebrew/bin/axe")
  #expect(
    AppleCommandBuilder.axeKeyboard(
      axe: axe, udid: "DEVICE", macKeyCode: 0, characters: "a",
      charactersIgnoringModifiers: "a", modifiers: []
    )?.arguments == ["type", "a", "--udid", "DEVICE"])
  #expect(
    AppleCommandBuilder.axeKeyboard(
      axe: axe, udid: "DEVICE", macKeyCode: 0, characters: "a",
      charactersIgnoringModifiers: "a", modifiers: [.command]
    )?.arguments == [
      "key-combo", "--modifiers", "227", "--key", "4", "--udid", "DEVICE",
    ])
  #expect(
    AppleCommandBuilder.axeKeyboard(
      axe: axe, udid: "DEVICE", macKeyCode: 51, characters: nil,
      charactersIgnoringModifiers: nil, modifiers: []
    )?.arguments == ["key", "42", "--udid", "DEVICE"])
}

@Test func processOutputIsBoundedAndMarked() async throws {
  let runner = ProcessRunner()
  let result = try await runner.run(
    executable: URL(fileURLWithPath: "/usr/bin/printf"),
    arguments: ["1234567890"], maximumOutputBytes: 5)
  #expect(result.stdout.hasPrefix("12345"))
  #expect(result.stdout.contains("output truncated"))
}

@Test func cocoaPodsPreflightRequiresLockedInstallation() throws {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data("platform :ios, '17.0'\n".utf8).write(to: directory.appending(path: "Podfile"))
  try Data("PODS:\n  - Example\n".utf8).write(to: directory.appending(path: "Podfile.lock"))
  let container = directory.appending(path: "Example.xcworkspace")

  let missing = try #require(CocoaPodsSupport.missingInstallation(for: container))
  #expect(missing.installArguments == ["install", "--deployment"])
  #expect(missing.reason.contains("Manifest.lock"))

  let support = directory.appending(path: "Pods/Target Support Files")
  try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
  try Data("different\n".utf8).write(to: directory.appending(path: "Pods/Manifest.lock"))
  #expect(
    CocoaPodsSupport.missingInstallation(for: container)?.reason.contains("do not match") == true)

  try Data("PODS:\n  - Example\n".utf8).write(to: directory.appending(path: "Pods/Manifest.lock"))
  #expect(CocoaPodsSupport.missingInstallation(for: container) == nil)
}

@Test func archiveChecksumValidationRejectsMismatch() throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  try Data("archive".utf8).write(to: url)
  let checksum = try ArchiveValidator.sha256(of: url)
  #expect(checksum.count == 64)
  #expect(throws: (any Error).self) {
    try ArchiveValidator.validate(url, expectedSHA256: String(repeating: "0", count: 64))
  }
}

@Test func normalizedPreviewCoordinatesAreClampedAndScaled() {
  let point = WDANormalizedPoint(x: 1.2, y: -0.4)
  #expect(point == WDANormalizedPoint(x: 1, y: 0))
  let scaled = WDANormalizedPoint(x: 0.25, y: 0.75).scaled(width: 390, height: 844)
  #expect(scaled.x == 97.5)
  #expect(scaled.y == 633)
}
