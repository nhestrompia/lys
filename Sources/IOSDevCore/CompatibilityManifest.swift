import CryptoKit
import Foundation

public struct WDACompatibilityManifest: Codable, Sendable {
  public struct Entry: Codable, Identifiable, Sendable {
    public var id: String { xcodeBuild }
    public var xcodeBuild: String
    public var xcodeVersion: String
    public var commit: String
    public var patchSet: String
    public var archiveURL: URL
    public var sourceSHA256: String
    public var validatedRuntimes: [String]
    public var integrationResult: String
  }
  public var schemaVersion: Int
  public var entries: [Entry]
  public static func load(from url: URL) throws -> Self {
    let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    guard value.schemaVersion == 1 else {
      throw RPCError(code: -32070, message: "Unsupported WDA compatibility manifest")
    }
    return value
  }
  public static func bundled() throws -> Self {
    guard let url = Bundle.module.url(forResource: "wda-compatibility", withExtension: "json")
    else { throw RPCError(code: -32070, message: "Bundled WDA compatibility manifest is missing") }
    return try load(from: url)
  }
  public func entry(xcodeBuild: String) -> Entry? {
    entries.first { $0.xcodeBuild == xcodeBuild && $0.integrationResult == "passed" }
  }
}

public enum WDAAvailability: String, Codable, Sendable {
  case unsupported
  case setupRequired
  case ready
}

public struct WDAStatus: Codable, Sendable {
  public var availability: WDAAvailability
  public var title: String
  public var detail: String
  public var entry: WDACompatibilityManifest.Entry?
  public var cacheDirectory: URL?
  public init(
    availability: WDAAvailability, title: String, detail: String,
    entry: WDACompatibilityManifest.Entry?, cacheDirectory: URL?
  ) {
    self.availability = availability
    self.title = title
    self.detail = detail
    self.entry = entry
    self.cacheDirectory = cacheDirectory
  }
}

public struct WDAValidationReceipt: Codable, Sendable {
  public var xcodeBuild: String
  public var runtime: String
  public var commit: String
  public var sourceSHA256: String
  public var builtAt: Date
  public var xctestrunPath: String
}

public enum WDACompatibilityGate {
  public static func status(
    preflight: ToolchainPreflight?, runtime: String?, stateRoot: URL,
    manifest: WDACompatibilityManifest? = try? .bundled()
  ) -> WDAStatus {
    guard let build = preflight?.xcodeBuild, let version = preflight?.xcodeVersion,
      let manifest, let entry = manifest.entry(xcodeBuild: build)
    else {
      let found = preflight?.xcodeBuild.map { "Xcode build \($0)" } ?? "the selected Xcode build"
      return .init(
        availability: .unsupported, title: "Semantic UI automation unavailable",
        detail: "No release-validated WebDriverAgent entry is promoted for \(found).",
        entry: nil, cacheDirectory: nil)
    }
    guard let runtime else {
      return .init(
        availability: .setupRequired, title: "WebDriverAgent validated for Xcode \(version)",
        detail: "Select a supported Simulator runtime to finish local setup.", entry: entry,
        cacheDirectory: nil)
    }
    guard entry.validatedRuntimes.contains(runtime) else {
      return .init(
        availability: .unsupported, title: "Simulator runtime not validated",
        detail:
          "Xcode \(version) is supported, but \(displayName(forRuntime: runtime)) is not in the promoted compatibility entry.",
        entry: entry, cacheDirectory: nil)
    }
    let cache = cacheDirectory(stateRoot: stateRoot, entry: entry, runtime: runtime)
    guard let receipt = try? loadReceipt(from: cache),
      receipt.xcodeBuild == build, receipt.runtime == runtime, receipt.commit == entry.commit,
      receipt.sourceSHA256.lowercased() == entry.sourceSHA256.lowercased(),
      FileManager.default.fileExists(atPath: receipt.xctestrunPath)
    else {
      return .init(
        availability: .setupRequired, title: "WebDriverAgent compatibility passed",
        detail:
          "Validated for Xcode \(version) and \(displayName(forRuntime: runtime)). Build the pinned runner once on this Mac.",
        entry: entry, cacheDirectory: cache)
    }
    return .init(
      availability: .ready, title: "Semantic UI automation ready",
      detail:
        "Pinned WebDriverAgent is built for Xcode \(version) and \(displayName(forRuntime: runtime)), with loopback-only transport.",
      entry: entry, cacheDirectory: cache)
  }

  public static func cacheDirectory(
    stateRoot: URL, entry: WDACompatibilityManifest.Entry, runtime: String
  ) -> URL {
    stateRoot.appending(path: entry.xcodeBuild, directoryHint: .isDirectory)
      .appending(path: runtime, directoryHint: .isDirectory)
  }

  public static func loadReceipt(from cache: URL) throws -> WDAValidationReceipt {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      WDAValidationReceipt.self, from: Data(contentsOf: cache.appending(path: "receipt.json")))
  }

  public static func saveReceipt(_ receipt: WDAValidationReceipt, to cache: URL) throws {
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(receipt).write(to: cache.appending(path: "receipt.json"), options: .atomic)
  }

  private static func displayName(forRuntime identifier: String) -> String {
    let prefix = "com.apple.CoreSimulator.SimRuntime."
    guard identifier.hasPrefix(prefix) else { return identifier }
    let value = identifier.dropFirst(prefix.count).replacingOccurrences(of: "-", with: ".")
    return value.replacingOccurrences(of: "iOS.", with: "iOS ")
  }
}

public enum ArchiveValidator {
  public static func sha256(of url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)).map {
      String(format: "%02x", $0)
    }.joined()
  }
  public static func validate(_ url: URL, expectedSHA256: String) throws {
    guard try sha256(of: url).lowercased() == expectedSHA256.lowercased() else {
      throw RPCError(
        code: -32071,
        message: "Downloaded archive checksum does not match the signed compatibility manifest")
    }
  }
}
