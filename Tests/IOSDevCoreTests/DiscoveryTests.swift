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

@Test func bundledWDAManifestPromotesOnlyTheValidatedXcodeBuildAndRuntime() throws {
  let manifest = try WDACompatibilityManifest.bundled()
  let entry = try #require(manifest.entry(xcodeBuild: "17F113"))
  #expect(entry.commit == "1449d94fb612a4e92857e7f37092dd1276b483e4")
  #expect(entry.validatedRuntimes == ["com.apple.CoreSimulator.SimRuntime.iOS-26-5"])
  #expect(manifest.entry(xcodeBuild: "unvalidated") == nil)
}
