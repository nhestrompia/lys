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
    // `lysd` and `lys-mcp` are shipped as loose helper executables inside
    // Lys.app/Contents/Resources/bin. `Bundle.main` therefore points at the
    // helper directory, while SwiftPM places the resource bundle alongside
    // that directory in Contents/Resources. Search both locations (and the
    // normal SwiftPM build output ancestors) before touching Bundle.module.
    // Bundle.module uses fatalError when its generated path is unavailable,
    // which would otherwise take down the whole host runtime during WDA setup.
    guard let resourceBundle = resourceBundle(named: "Lys_IOSDevCore.bundle") else {
      throw RPCError(code: -32070, message: "Bundled WDA compatibility resources are missing")
    }
    guard let url = resourceBundle.url(forResource: "wda-compatibility", withExtension: "json")
    else { throw RPCError(code: -32070, message: "Bundled WDA compatibility manifest is missing") }
    return try load(from: url)
  }

  private static func resourceBundle(named name: String) -> Bundle? {
    var roots: [URL] = []
    func appendRoot(_ root: URL?) {
      guard let root else { return }
      let normalized = root.standardizedFileURL
      if !roots.contains(normalized) { roots.append(normalized) }
    }

    appendRoot(Bundle.main.resourceURL)
    appendRoot(Bundle.main.bundleURL)
    appendRoot(Bundle.main.executableURL?.deletingLastPathComponent())
    if let executable = CommandLine.arguments.first {
      appendRoot(URL(fileURLWithPath: executable).deletingLastPathComponent())
    }

    return resourceBundle(named: name, roots: roots)
  }

  static func resourceBundle(named name: String, roots: [URL]) -> Bundle? {

    // A raw executable may report either its directory or its own path as the
    // bundle URL. Walking a few parents covers both the installed app layout
    // and SwiftPM's .build/<triple>/<configuration> output.
    var candidates: [URL] = []
    for root in roots {
      var current = root
      for _ in 0..<5 {
        if !candidates.contains(current) { candidates.append(current) }
        current = current.deletingLastPathComponent()
      }
    }

    for directory in candidates {
      let path = directory.appending(path: name)
      if let bundle = Bundle(path: path.path) { return bundle }
    }
#if DEBUG
    // SwiftPM's test runner can execute through the package manager helper,
    // whose Bundle.main is not the test binary. The generated module accessor
    // has a valid build-output fallback in debug builds; never use this path
    // in the shipped release helpers, where it may call fatalError.
    let development = Bundle.module
    if development.url(forResource: "wda-compatibility", withExtension: "json") != nil {
      return development
    }
#endif
    return nil
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
          "Validated for Xcode \(version) and \(displayName(forRuntime: runtime)). Lys will prepare the pinned runner automatically before semantic testing.",
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
