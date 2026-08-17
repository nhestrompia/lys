import Foundation
import Testing

@testable import IOSDevCore

@Test func workspacePrecedesProjectAndInternalWorkspaceIsExcluded() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let workspace = root.appending(path: "Demo.xcworkspace")
  let project = root.appending(path: "Demo.xcodeproj")
  try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(
    at: project.appending(path: "project.xcworkspace"), withIntermediateDirectories: true)
  #expect(
    ToolchainDiscovery.projectContainers(in: root).map(\.lastPathComponent) == [
      "Demo.xcworkspace", "Demo.xcodeproj",
    ])
}

@Test func dependencyContainersAreExcludedAndApplicationSchemeIsPreferred() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let workspace = root.appending(path: "Ellinix.xcworkspace")
  let project = root.appending(path: "Ellinix.xcodeproj")
  let podsProject = root.appending(path: "Pods/Pods.xcodeproj")
  try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: podsProject, withIntermediateDirectories: true)

  #expect(
    ToolchainDiscovery.projectContainers(in: root).map(\.lastPathComponent) == [
      "Ellinix.xcworkspace", "Ellinix.xcodeproj",
    ])
  #expect(
    ToolchainDiscovery.prioritizeSchemes(
      ["boost", "Pods-Ellinix", "Ellinix", "React-Core"], for: workspace) == [
        "Ellinix", "boost", "Pods-Ellinix", "React-Core",
      ])
}

@Test func expoFmtRepairIsNarrowAndIdempotent() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let header = root.appending(path: "Pods/fmt/include/fmt/base.h")
  try FileManager.default.createDirectory(
    at: header.deletingLastPathComponent(), withIntermediateDirectories: true)
  try """
  #elif defined(__apple_build_version__) && __apple_build_version__ < 14000029L
  #  define FMT_USE_CONSTEVAL 0
  #elif defined(__cpp_consteval)
  #  define FMT_USE_CONSTEVAL 1
  """.write(to: header, atomically: true, encoding: .utf8)

  #expect(ExpoCompatibility.needsFMTConstevalRepair(at: header))
  #expect(try ExpoCompatibility.applyFMTConstevalRepair(at: header))
  #expect(!ExpoCompatibility.needsFMTConstevalRepair(at: header))
  #expect(try !ExpoCompatibility.applyFMTConstevalRepair(at: header))
  let patched = try String(contentsOf: header, encoding: .utf8)
  #expect(patched.contains("__apple_build_version__ >= 21000000L"))
  #expect(patched.contains("__apple_build_version__ < 14000029L"))
}

@Test func expoMMKVRepairUsesPortableSecureWipeAndIsIdempotent() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let source = root.appending(path: "Pods/MMKVCore/Core/aes/AESCrypt.cpp")
  try FileManager.default.createDirectory(
    at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
  try """
  #elif defined(__STDC_LIB_EXT1__) || defined(MMKV_APPLE)
      // C11 Annex K, if the implementation actually provides it.
      (void)memset_s(ptr, len, 0, len);
  #elif defined(__GLIBC__)
  """.write(to: source, atomically: true, encoding: .utf8)

  #expect(ExpoCompatibility.needsMMKVSecureWipeRepair(at: source))
  #expect(try ExpoCompatibility.applyMMKVSecureWipeRepair(at: source))
  #expect(!ExpoCompatibility.needsMMKVSecureWipeRepair(at: source))
  #expect(try !ExpoCompatibility.applyMMKVSecureWipeRepair(at: source))
  let patched = try String(contentsOf: source, encoding: .utf8)
  #expect(patched.contains("volatile unsigned char*"))
  #expect(patched.contains("#elif defined(MMKV_APPLE)"))
}

@Test func adapterDetectionDoesNotExecuteShellInitialization() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let executable = root.appending(path: "opencode")
  #expect(FileManager.default.createFile(atPath: executable.path, contents: Data()))
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
  let adapter = AdapterManager.detect(path: root.path).first { $0.id == "opencode" }
  #expect(adapter?.executable == executable)
  #expect(adapter?.launchArguments == ["acp"])
}

@Test func adapterDetectionFindsConventionalUserBinAndDistinguishesConfiguration() throws {
  let home = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let localBin = home.appending(path: ".local/bin")
  try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
  let codex = localBin.appending(path: "codex")
  #expect(FileManager.default.createFile(atPath: codex.path, contents: Data()))
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
  try FileManager.default.createDirectory(
    at: home.appending(path: ".config/opencode"), withIntermediateDirectories: true)

  let adapters = AdapterManager.detect(path: "/usr/bin", homeDirectory: home)
  let detectedCodex = adapters.first { $0.id == "codex" }
  #expect(detectedCodex?.cliExecutable == codex)
  #expect(detectedCodex?.availability == .cliDetected)
  #expect(adapters.first { $0.id == "opencode" }?.availability == .configurationOnly)
}

@Test func pinnedNpmAdaptersAreProvisionableWithoutTreatingOpenCodeAsAnAdapterPackage() throws {
  let entries = AdapterManager.pinned
  #expect(
    entries.compactMap(AdapterManager.npmPackage(for:)) == [
      "@agentclientprotocol/codex-acp",
      "@agentclientprotocol/claude-agent-acp",
      "pi-acp",
    ])
  #expect(AdapterManager.npmPackage(for: entries.first { $0.id == "opencode" }!) == nil)
}

@Test func managedAdapterPathsAndRuntimePathAreStable() throws {
  let root = URL(fileURLWithPath: "/tmp/lys-adapters")
  let entry = try #require(AdapterManager.pinned.first { $0.id == "codex" })
  let managedBin = AdapterManager.managedExecutableDirectory(for: entry, in: root)
  #expect(
    managedBin.path == "/tmp/lys-adapters/codex/1.1.14/node_modules/.bin")

  let adapter = DetectedAdapter(
    id: "codex", displayName: "Codex", executable: managedBin.appending(path: "codex-acp"),
    cliExecutable: nil, configurationDetected: false, launchArguments: [], mode: "read-write",
    limitation: nil, availability: .ready)
  let environment = AdapterManager.runtimeEnvironment(
    for: adapter, inherited: ["PATH": "/custom/bin"],
    homeDirectory: URL(fileURLWithPath: "/Users/test"))
  #expect(
    environment["PATH"] == "/tmp/lys-adapters/codex/1.1.14/node_modules/.bin:/opt/homebrew/bin:/usr/local/bin:/Users/test/.local/bin:/Users/test/.bun/bin:/Users/test/.volta/bin:/Users/test/Library/pnpm:/usr/bin:/bin:/usr/sbin:/sbin:/custom/bin")
}

@Test func adapterProvisioningUsesTheManagedPrefixAndPinnedPackage() async throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let npm = root.appending(path: "npm")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try """
  #!/bin/sh
  prefix=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--prefix" ]; then prefix="$2"; shift 2; else shift; fi
  done
  mkdir -p "$prefix/node_modules/.bin"
  touch "$prefix/node_modules/.bin/codex-acp"
  chmod 755 "$prefix/node_modules/.bin/codex-acp"
  """.write(to: npm, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: npm.path)

  let entry = try #require(AdapterManager.pinned.first { $0.id == "codex" })
  let cli = URL(fileURLWithPath: "/usr/bin/codex")
  let detected = DetectedAdapter(
    id: "codex", displayName: "Codex", executable: nil, cliExecutable: cli,
    configurationDetected: false, launchArguments: [], mode: "unavailable",
    limitation: "setup", availability: .cliDetected)

  let report = await AdapterManager.provisionMissing(
    detected: [detected], entries: [entry], npm: npm, managedRoot: root)
  #expect(report.installedAdapterIDs == ["codex"])
  #expect(report.failures.isEmpty)
  #expect(
    FileManager.default.fileExists(
      atPath: AdapterManager.managedExecutableDirectory(for: entry, in: root)
        .appending(path: "codex-acp").path))
}

@Test func bundledWDAManifestPromotesOnlyTheValidatedXcodeBuildAndRuntime() throws {
  let manifest = try WDACompatibilityManifest.bundled()
  let entry = try #require(manifest.entry(xcodeBuild: "17F113"))
  #expect(entry.commit == "1449d94fb612a4e92857e7f37092dd1276b483e4")
  #expect(entry.validatedRuntimes == ["com.apple.CoreSimulator.SimRuntime.iOS-26-5"])
  #expect(manifest.entry(xcodeBuild: "unvalidated") == nil)
}

@Test func packagedHelperResourceLookupWalksFromBinToAppResources() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let resources = root.appending(path: "Lys.app/Contents/Resources", directoryHint: .isDirectory)
  let bundle = resources.appending(path: "Lys_IOSDevCore.bundle", directoryHint: .isDirectory)
  let helperDirectory = resources.appending(path: "bin", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
  try "{\"schemaVersion\":1,\"entries\":[]}".write(
    to: bundle.appending(path: "wda-compatibility.json"), atomically: true, encoding: .utf8)

  let located = WDACompatibilityManifest.resourceBundle(
    named: "Lys_IOSDevCore.bundle", roots: [helperDirectory])
  #expect(located?.url(forResource: "wda-compatibility", withExtension: "json") != nil)
}
