import Foundation

public struct ToolchainPreflight: Codable, Sendable {
  public var developerDirectory: String?
  public var xcodebuildPath: String?
  public var simctlPath: String?
  public var xcodeVersion: String?
  public var xcodeBuild: String?
  public var isFullXcode: Bool
  public var issues: [String]
  public init(
    developerDirectory: String?, xcodebuildPath: String?, simctlPath: String?,
    xcodeVersion: String?, xcodeBuild: String?, isFullXcode: Bool, issues: [String]
  ) {
    self.developerDirectory = developerDirectory
    self.xcodebuildPath = xcodebuildPath
    self.simctlPath = simctlPath
    self.xcodeVersion = xcodeVersion
    self.xcodeBuild = xcodeBuild
    self.isFullXcode = isFullXcode
    self.issues = issues
  }
}

public struct ProjectListing: Codable, Sendable {
  public var container: URL
  public var schemes: [String]
  public var targets: [String]
  public var configurations: [String]
}

public enum ToolchainDiscovery {
  public static func preflight(developerDirectory: URL? = nil) async -> ToolchainPreflight {
    let runner = ProcessRunner()
    var issues: [String] = []
    let os = ProcessInfo.processInfo.operatingSystemVersion
    if os.majorVersion < 26 || (os.majorVersion == 26 && os.minorVersion < 2) {
      issues.append("The public alpha requires macOS 26.2 or newer")
    }
    let selected: String?
    if let developerDirectory {
      selected = developerDirectory.path
    } else if let environmentDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
      !environmentDirectory.isEmpty
    {
      selected = environmentDirectory
    } else if let outcome = try? await runner.run(
      executable: URL(fileURLWithPath: "/usr/bin/xcode-select"), arguments: ["-p"]),
      outcome.succeeded
    {
      selected = outcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      selected = nil
    }
    guard let selected else {
      return .init(
        developerDirectory: nil, xcodebuildPath: nil, simctlPath: nil, xcodeVersion: nil,
        xcodeBuild: nil, isFullXcode: false, issues: ["No active developer directory"])
    }
    let usrBin = URL(fileURLWithPath: selected).appending(path: "usr/bin")
    let xcodebuild = usrBin.appending(path: "xcodebuild")
    let simctl = usrBin.appending(path: "simctl")
    let fileManager = FileManager.default
    let full =
      fileManager.isExecutableFile(atPath: xcodebuild.path)
      && fileManager.isExecutableFile(atPath: simctl.path)
    if !full {
      issues.append(
        "Select a full Xcode installation; Command Line Tools do not include xcodebuild and simctl")
    }
    var version: String?
    var build: String?
    if full, let output = try? await runner.run(executable: xcodebuild, arguments: ["-version"]),
      output.succeeded
    {
      for line in output.stdout.split(separator: "\n") {
        if line.hasPrefix("Xcode ") { version = line.dropFirst(6).description }
        if line.hasPrefix("Build version ") { build = line.dropFirst(14).description }
      }
      if version != "26.5" {
        issues.append(
          "Public alpha compatibility is pinned to Xcode 26.5; found \(version ?? "unknown")")
      }
    }
    return .init(
      developerDirectory: selected, xcodebuildPath: full ? xcodebuild.path : nil,
      simctlPath: full ? simctl.path : nil, xcodeVersion: version, xcodeBuild: build,
      isFullXcode: full, issues: issues)
  }

  public static func projectContainers(in root: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    else { return [] }
    var workspaces: [URL] = []
    var projects: [URL] = []
    while let url = enumerator.nextObject() as? URL {
      if ["Pods", "node_modules", "Carthage", "SourcePackages", "DerivedData", ".build"]
        .contains(url.lastPathComponent)
      {
        enumerator.skipDescendants()
        continue
      }
      if url.pathExtension == "xcworkspace" {
        if !url.path.contains(".xcodeproj/project.xcworkspace") { workspaces.append(url) }
        enumerator.skipDescendants()
      } else if url.pathExtension == "xcodeproj" {
        projects.append(url)
        enumerator.skipDescendants()
      }
    }
    return workspaces.sorted { $0.path < $1.path } + projects.sorted { $0.path < $1.path }
  }

  public static func prioritizeSchemes(_ schemes: [String], for container: URL) -> [String] {
    let containerName = container.deletingPathExtension().lastPathComponent
    return schemes.enumerated().sorted { left, right in
      let leftExact = left.element.caseInsensitiveCompare(containerName) == .orderedSame
      let rightExact = right.element.caseInsensitiveCompare(containerName) == .orderedSame
      if leftExact != rightExact { return leftExact }
      return left.offset < right.offset
    }.map(\.element)
  }

  public static func listProject(container: URL, xcodebuild: URL, developerDirectory: URL)
    async throws -> ProjectListing
  {
    let flag = container.pathExtension == "xcworkspace" ? "-workspace" : "-project"
    let outcome = try await ProcessRunner().run(
      executable: xcodebuild, arguments: [flag, container.path, "-list", "-json"],
      workingDirectory: container.deletingLastPathComponent(),
      environment: ["DEVELOPER_DIR": developerDirectory.path])
    guard outcome.succeeded else {
      throw RPCError(
        code: -32050, message: "xcodebuild project listing failed", data: .string(outcome.stderr))
    }
    let root = try JSONDecoder().decode(JSONValue.self, from: Data(outcome.stdout.utf8))
    let section = root[container.pathExtension == "xcworkspace" ? "workspace" : "project"]
    func strings(_ key: String) -> [String] {
      guard case .array(let values) = section?[key] else { return [] }
      return values.compactMap(\.stringValue)
    }
    return .init(
      container: container, schemes: strings("schemes"), targets: strings("targets"),
      configurations: strings("configurations"))
  }

  public static func simulators(simctl: URL, developerDirectory: URL) async throws -> [Destination]
  {
    let outcome = try await ProcessRunner().run(
      executable: simctl, arguments: ["list", "devices", "-j"],
      environment: ["DEVELOPER_DIR": developerDirectory.path])
    guard outcome.succeeded else {
      throw RPCError(code: -32051, message: "simctl list failed", data: .string(outcome.stderr))
    }
    struct Response: Decodable {
      struct Device: Decodable {
        var state: String
        var isAvailable: Bool
        var name: String
        var udid: String
        var deviceTypeIdentifier: String?
      }
      var devices: [String: [Device]]
    }
    let response = try JSONDecoder().decode(Response.self, from: Data(outcome.stdout.utf8))
    let destinations: [Destination] = response.devices.flatMap { runtime, devices in
      devices.filter(\.isAvailable).map {
        .init(
          udid: $0.udid, name: $0.name, deviceType: $0.deviceTypeIdentifier ?? "unknown",
          runtime: runtime, state: $0.state)
      }
    }
    func rank(_ destination: Destination) -> Int {
      var value = 0
      if destination.state.caseInsensitiveCompare("Booted") == .orderedSame { value -= 1_000 }
      if destination.name.hasPrefix("iPhone") { value -= 100 }
      if destination.runtime.contains("iOS-26-5") { value -= 20 }
      if destination.name.contains("Pro") { value -= 5 }
      return value
    }
    return destinations.sorted {
      let left = rank($0)
      let right = rank($1)
      return left == right
        ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
        : left < right
    }
  }

  public static func distributionTarget(
    container: URL, scheme: String, xcodebuild: URL, developerDirectory: URL,
    derivedData: URL
  ) async throws -> LocalDistributionTarget {
    let flag = container.pathExtension == "xcworkspace" ? "-workspace" : "-project"
    let outcome = try await ProcessRunner().run(
      executable: xcodebuild,
      arguments: [
        flag, container.path, "-scheme", scheme, "-configuration", "Release",
        "-destination", "generic/platform=iOS", "-derivedDataPath", derivedData.path,
        "-showBuildSettings", "-json",
      ], workingDirectory: container.deletingLastPathComponent(),
      environment: ["DEVELOPER_DIR": developerDirectory.path])
    guard outcome.succeeded else {
      throw AppStoreDistributionError.commandFailed(
        stage: "Release build-settings discovery",
        detail: outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    struct Entry: Decodable {
      var target: String
      var buildSettings: [String: JSONValue]
    }
    let entries = try JSONDecoder().decode([Entry].self, from: Data(outcome.stdout.utf8))
    guard let entry = entries.first(where: {
      $0.buildSettings["WRAPPER_EXTENSION"]?.stringValue == "app"
        && $0.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?.stringValue != nil
    }) else {
      throw AppStoreDistributionError.missingBuildSetting("iOS application target")
    }
    func required(_ key: String) throws -> String {
      guard let value = entry.buildSettings[key]?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
      else { throw AppStoreDistributionError.missingBuildSetting(key) }
      return value
    }
    func optional(_ key: String) -> String? {
      let value = entry.buildSettings[key]?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return value.flatMap { $0.isEmpty ? nil : $0 }
    }
    let stringBuildSettings = entry.buildSettings.compactMapValues(\.stringValue)
    let infoPlistFile = sourceInfoPlistURL(
      buildSettings: stringBuildSettings, container: container)
    let usesGeneratedInfoPlist = ["YES", "TRUE", "1"].contains {
      stringBuildSettings["GENERATE_INFOPLIST_FILE"]?.caseInsensitiveCompare($0) == .orderedSame
    }
    let bundleVersions = effectiveBundleVersions(
      buildSettings: stringBuildSettings, container: container)
    guard let marketingVersion = bundleVersions.marketingVersion else {
      throw AppStoreDistributionError.missingBuildSetting(
        "CFBundleShortVersionString or MARKETING_VERSION")
    }
    guard let buildNumber = bundleVersions.buildNumber else {
      throw AppStoreDistributionError.missingBuildSetting(
        "CFBundleVersion or CURRENT_PROJECT_VERSION")
    }
    return try .init(
      container: container, scheme: scheme, target: entry.target,
      bundleID: required("PRODUCT_BUNDLE_IDENTIFIER"),
      productName: required("PRODUCT_NAME"), marketingVersion: marketingVersion,
      buildNumber: buildNumber,
      developmentTeam: optional("DEVELOPMENT_TEAM"), codeSignStyle: optional("CODE_SIGN_STYLE"),
      codeSignIdentity: optional("CODE_SIGN_IDENTITY"),
      provisioningProfileSpecifier: optional("PROVISIONING_PROFILE_SPECIFIER"),
      entitlementsPath: optional("CODE_SIGN_ENTITLEMENTS"), infoPlistFile: infoPlistFile,
      usesGeneratedInfoPlist: usesGeneratedInfoPlist)
  }

  static func effectiveBundleVersions(
    buildSettings: [String: String], infoPlist: [String: Any]?
  ) -> (marketingVersion: String?, buildNumber: String?) {
    (
      effectiveBundleValue(
        plistKey: "CFBundleShortVersionString", fallbackBuildSetting: "MARKETING_VERSION",
        buildSettings: buildSettings, infoPlist: infoPlist),
      effectiveBundleValue(
        plistKey: "CFBundleVersion", fallbackBuildSetting: "CURRENT_PROJECT_VERSION",
        buildSettings: buildSettings, infoPlist: infoPlist)
    )
  }

  static func effectiveBundleVersions(
    buildSettings: [String: String], container: URL
  ) -> (marketingVersion: String?, buildNumber: String?) {
    effectiveBundleVersions(
      buildSettings: buildSettings,
      infoPlist: resolvedInfoPlist(buildSettings: buildSettings, container: container))
  }

  private static func effectiveBundleValue(
    plistKey: String, fallbackBuildSetting: String, buildSettings: [String: String],
    infoPlist: [String: Any]?
  ) -> String? {
    if let value = infoPlist?[plistKey] as? String,
      let resolved = normalizedBuildValue(expand(value, with: buildSettings)),
      !resolved.contains("$("), !resolved.contains("${")
    {
      return resolved
    }
    return normalizedBuildValue(buildSettings[fallbackBuildSetting])
  }

  private static func resolvedInfoPlist(
    buildSettings: [String: String], container: URL
  ) -> [String: Any]? {
    guard let plistURL = sourceInfoPlistURL(buildSettings: buildSettings, container: container)
    else { return nil }
    guard let data = try? Data(contentsOf: plistURL.standardizedFileURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else {
      return nil
    }
    return plist
  }

  private static func sourceInfoPlistURL(
    buildSettings: [String: String], container: URL
  ) -> URL? {
    guard let rawPath = normalizedBuildValue(buildSettings["INFOPLIST_FILE"]) else {
      return nil
    }
    let path = expand(rawPath, with: buildSettings)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    let baseURL = ["SRCROOT", "PROJECT_DIR"]
      .compactMap { normalizedBuildValue(buildSettings[$0]) }
      .map { URL(fileURLWithPath: expand($0, with: buildSettings), isDirectory: true) }
      .first ?? container.deletingLastPathComponent()
    return path.hasPrefix("/")
      ? URL(fileURLWithPath: path).standardizedFileURL
      : baseURL.appending(path: path).standardizedFileURL
  }

  private static func expand(_ rawValue: String, with buildSettings: [String: String]) -> String {
    var value = rawValue
    for _ in 0..<4 {
      let previous = value
      for (key, replacement) in buildSettings {
        value = value.replacingOccurrences(of: "$(\(key))", with: replacement)
        value = value.replacingOccurrences(of: "${\(key)}", with: replacement)
      }
      if value == previous { break }
    }
    return value
  }

  private static func normalizedBuildValue(_ value: String?) -> String? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.flatMap { $0.isEmpty ? nil : $0 }
  }

  public static func signingIdentities(
    security: URL = URL(fileURLWithPath: "/usr/bin/security")
  ) async throws -> [DistributionSigningIdentity] {
    let outcome = try await ProcessRunner().run(
      executable: security, arguments: ["find-identity", "-v", "-p", "codesigning"],
      maximumOutputBytes: 1_000_000)
    guard outcome.succeeded else {
      throw AppStoreDistributionError.commandFailed(
        stage: "Signing identity discovery",
        detail: outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return AppStoreDistributionSupport.parseSigningIdentities(outcome.stdout)
  }

  public static func appTargets(
    container: URL, scheme: String, configuration: String, destination: String,
    xcodebuild: URL, developerDirectory: URL, derivedData: URL
  ) async throws -> [AppTarget] {
    let flag = container.pathExtension == "xcworkspace" ? "-workspace" : "-project"
    let outcome = try await ProcessRunner().run(
      executable: xcodebuild,
      arguments: [
        flag, container.path, "-scheme", scheme, "-configuration", configuration,
        "-destination", destination, "-derivedDataPath", derivedData.path,
        "-showBuildSettings", "-json",
      ], workingDirectory: container.deletingLastPathComponent(),
      environment: ["DEVELOPER_DIR": developerDirectory.path])
    guard outcome.succeeded else {
      throw RPCError(
        code: -32055, message: "xcodebuild build-settings discovery failed",
        data: .string(outcome.stderr))
    }
    struct Entry: Decodable {
      var target: String
      var buildSettings: [String: JSONValue]
    }
    let entries = try JSONDecoder().decode([Entry].self, from: Data(outcome.stdout.utf8))
    return entries.compactMap { entry in
      func string(_ key: String) -> String? { entry.buildSettings[key]?.stringValue }
      guard string("WRAPPER_EXTENSION") == "app",
        let bundleID = string("PRODUCT_BUNDLE_IDENTIFIER"),
        let targetDirectory = string("TARGET_BUILD_DIR"),
        let productName = string("FULL_PRODUCT_NAME")
      else { return nil }
      return AppTarget(
        container: container, scheme: scheme, configuration: configuration, target: entry.target,
        bundleID: bundleID,
        productPath: URL(fileURLWithPath: targetDirectory).appending(path: productName))
    }
  }
}
