import Foundation

public actor WDAInstaller {
  private let runner = ProcessRunner()

  public init() {}

  public func install(
    entry: WDACompatibilityManifest.Entry, runtime: String, destinationUDID: String,
    stateRoot: URL, xcodebuild: URL, developerDirectory: URL
  ) async throws -> WDAValidationReceipt {
    let finalCache = WDACompatibilityGate.cacheDirectory(
      stateRoot: stateRoot, entry: entry, runtime: runtime)
    let staging = stateRoot.appending(
      path: ".setup-\(entry.xcodeBuild)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    do {
      let archive = staging.appending(path: "WebDriverAgent.tar.gz")
      let (temporary, response) = try await URLSession.shared.download(from: entry.archiveURL)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw RPCError(code: -32073, message: "WebDriverAgent download failed")
      }
      try Data(contentsOf: temporary).write(to: archive, options: .atomic)
      try ArchiveValidator.validate(archive, expectedSHA256: entry.sourceSHA256)
      try await validateArchivePaths(archive)

      let sources = staging.appending(path: "Source", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
      let extraction = try await runner.run(
        executable: URL(fileURLWithPath: "/usr/bin/tar"),
        arguments: ["-xzf", archive.path, "-C", sources.path], maximumOutputBytes: 2_000_000)
      guard extraction.succeeded else {
        throw RPCError(code: -32074, message: "Could not extract WebDriverAgent", data: .string(extraction.stderr))
      }
      guard let project = firstFile(withExtension: "xcodeproj", under: sources) else {
        throw RPCError(code: -32074, message: "WebDriverAgent.xcodeproj is missing from the verified archive")
      }
      let derivedData = staging.appending(path: "DerivedData", directoryHint: .isDirectory)
      let build = try await runner.run(
        executable: xcodebuild,
        arguments: [
          "-project", project.path, "-scheme", "WebDriverAgentRunner", "-destination",
          "id=\(destinationUDID)", "-derivedDataPath", derivedData.path,
          "CODE_SIGNING_ALLOWED=NO", "build-for-testing",
        ], workingDirectory: project.deletingLastPathComponent(),
        environment: ["DEVELOPER_DIR": developerDirectory.path],
        maximumOutputBytes: 24 * 1_024 * 1_024)
      guard build.succeeded else {
        throw RPCError(code: -32075, message: "WebDriverAgent failed to build", data: .string(build.stderr))
      }
      guard let originalRun = firstFile(withExtension: "xctestrun", under: derivedData) else {
        throw RPCError(code: -32075, message: "Xcode did not produce a WebDriverAgent xctestrun file")
      }
      let loopbackRun = originalRun.deletingLastPathComponent().appending(
        path: "WebDriverAgentRunner-loopback.xctestrun")
      try patchForLoopback(originalRun, output: loopbackRun)

      let relativeRun = loopbackRun.path.replacingOccurrences(of: staging.path + "/", with: "")
      if FileManager.default.fileExists(atPath: finalCache.path) {
        try FileManager.default.removeItem(at: finalCache)
      }
      try FileManager.default.createDirectory(
        at: finalCache.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.moveItem(at: staging, to: finalCache)
      let receipt = WDAValidationReceipt(
        xcodeBuild: entry.xcodeBuild, runtime: runtime, commit: entry.commit,
        sourceSHA256: entry.sourceSHA256, builtAt: Date(),
        xctestrunPath: finalCache.appending(path: relativeRun).path)
      try WDACompatibilityGate.saveReceipt(receipt, to: finalCache)
      return receipt
    } catch {
      try? FileManager.default.removeItem(at: staging)
      throw error
    }
  }

  private func validateArchivePaths(_ archive: URL) async throws {
    let listing = try await runner.run(
      executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tzf", archive.path],
      maximumOutputBytes: 8 * 1_024 * 1_024)
    guard listing.succeeded else {
      throw RPCError(code: -32074, message: "Could not inspect WebDriverAgent archive")
    }
    for path in listing.stdout.split(separator: "\n").map(String.init) {
      guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
        throw RPCError(code: -32074, message: "WebDriverAgent archive contains an unsafe path")
      }
    }
  }

  private func firstFile(withExtension extensionName: String, under root: URL) -> URL? {
    guard let values = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return nil }
    for case let url as URL in values where url.pathExtension == extensionName { return url }
    return nil
  }

  private func patchForLoopback(_ input: URL, output: URL) throws {
    let data = try Data(contentsOf: input)
    guard var root = try PropertyListSerialization.propertyList(from: data, format: nil)
      as? [String: Any],
      let testKey = root.keys.first(where: { $0 != "__xctestrun_metadata__" }),
      var test = root[testKey] as? [String: Any]
    else { throw RPCError(code: -32076, message: "Unsupported xctestrun format") }
    var environment = test["EnvironmentVariables"] as? [String: Any] ?? [:]
    environment["USE_IP"] = "127.0.0.1"
    environment["USE_PORT"] = "8100"
    test["EnvironmentVariables"] = environment
    root[testKey] = test
    let encoded = try PropertyListSerialization.data(
      fromPropertyList: root, format: .binary, options: 0)
    try encoded.write(to: output, options: .atomic)
  }
}
