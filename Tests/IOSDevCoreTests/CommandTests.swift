import Foundation
import Testing

@testable import IOSDevCore

@Test func simulatorCommandsPreserveArgumentsWithoutShellInterpolation() {
  let simctl = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl")
  let app = URL(fileURLWithPath: "/tmp/My App; touch nope.app")
  #expect(
    AppleCommandBuilder.install(simctl: simctl, udid: "DEVICE", app: app).arguments == [
      "install", "DEVICE", app.path,
    ])
  #expect(
    AppleCommandBuilder.launch(simctl: simctl, udid: "DEVICE", bundleID: "com.example.app")
      .arguments == ["launch", "DEVICE", "com.example.app"])
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
}

@Test func processOutputIsBoundedAndMarked() async throws {
  let runner = ProcessRunner()
  let result = try await runner.run(
    executable: URL(fileURLWithPath: "/usr/bin/printf"),
    arguments: ["1234567890"], maximumOutputBytes: 5)
  #expect(result.stdout.hasPrefix("12345"))
  #expect(result.stdout.contains("output truncated"))
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
