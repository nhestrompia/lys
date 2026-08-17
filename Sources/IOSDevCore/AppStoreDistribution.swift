import Foundation

public struct LocalDistributionTarget: Codable, Equatable, Sendable {
  public var container: URL
  public var scheme: String
  public var target: String
  public var bundleID: String
  public var productName: String
  public var marketingVersion: String
  public var buildNumber: String
  public var developmentTeam: String?
  public var codeSignStyle: String?
  public var codeSignIdentity: String?
  public var provisioningProfileSpecifier: String?
  public var entitlementsPath: String?
  public var infoPlistFile: URL?
  public var usesGeneratedInfoPlist: Bool

  public init(
    container: URL, scheme: String, target: String, bundleID: String, productName: String,
    marketingVersion: String, buildNumber: String, developmentTeam: String? = nil,
    codeSignStyle: String? = nil, codeSignIdentity: String? = nil,
    provisioningProfileSpecifier: String? = nil, entitlementsPath: String? = nil,
    infoPlistFile: URL? = nil, usesGeneratedInfoPlist: Bool = false
  ) {
    self.container = container
    self.scheme = scheme
    self.target = target
    self.bundleID = bundleID
    self.productName = productName
    self.marketingVersion = marketingVersion
    self.buildNumber = buildNumber
    self.developmentTeam = developmentTeam
    self.codeSignStyle = codeSignStyle
    self.codeSignIdentity = codeSignIdentity
    self.provisioningProfileSpecifier = provisioningProfileSpecifier
    self.entitlementsPath = entitlementsPath
    self.infoPlistFile = infoPlistFile
    self.usesGeneratedInfoPlist = usesGeneratedInfoPlist
  }
}

public struct DistributionSigningIdentity: Codable, Equatable, Sendable {
  public var fingerprint: String
  public var name: String

  public init(fingerprint: String, name: String) {
    self.fingerprint = fingerprint
    self.name = name
  }

  public var isDistributionIdentity: Bool {
    name.contains("Apple Distribution") || name.contains("iOS Distribution")
  }
}

public struct AppStoreArchiveInspection: Codable, Equatable, Sendable {
  public var bundleID: String
  public var marketingVersion: String
  public var buildNumber: String
  public var signingIdentity: String?
  public var teamID: String?
  public var applicationPath: String?
  public var architectures: [String]

  public init(
    bundleID: String, marketingVersion: String, buildNumber: String,
    signingIdentity: String? = nil, teamID: String? = nil, applicationPath: String? = nil,
    architectures: [String] = []
  ) {
    self.bundleID = bundleID
    self.marketingVersion = marketingVersion
    self.buildNumber = buildNumber
    self.signingIdentity = signingIdentity
    self.teamID = teamID
    self.applicationPath = applicationPath
    self.architectures = architectures
  }
}

public struct AppStoreDistributionAuthentication: Equatable, Sendable {
  public var privateKeyURL: URL
  public var keyID: String
  public var issuerID: String

  public init(privateKeyURL: URL, keyID: String, issuerID: String) {
    self.privateKeyURL = privateKeyURL
    self.keyID = keyID
    self.issuerID = issuerID
  }
}

public struct AppStoreInfoPlistBuildNumberOverride: Sendable {
  private let url: URL
  private let originalData: Data
  private let overriddenData: Data
  private let originalPOSIXPermissions: Int?

  fileprivate init(
    url: URL, originalData: Data, overriddenData: Data, originalPOSIXPermissions: Int?
  ) {
    self.url = url
    self.originalData = originalData
    self.overriddenData = overriddenData
    self.originalPOSIXPermissions = originalPOSIXPermissions
  }

  public func restore() throws {
    guard let currentData = try? Data(contentsOf: url), currentData == overriddenData else {
      throw AppStoreDistributionError.buildNumberOverrideFailed(
        "\(url.lastPathComponent) changed while the archive was running; Lys left it untouched."
      )
    }
    try originalData.write(to: url, options: .atomic)
    if let originalPOSIXPermissions {
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: originalPOSIXPermissions)], ofItemAtPath: url.path)
    }
  }
}

public struct AppStoreTemporaryCredential: Equatable, Sendable {
  public var directoryURL: URL
  public var privateKeyURL: URL

  public static func create(privateKey: Data, keyID: String, in jobRoot: URL) throws -> Self {
    let directory = jobRoot.appending(path: ".credentials", directoryHint: .isDirectory)
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: directory.path)
      let keyURL = directory.appending(path: "AuthKey_\(keyID).p8")
      try privateKey.write(to: keyURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
      return .init(directoryURL: directory, privateKeyURL: keyURL)
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  public func remove() throws {
    guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
    try FileManager.default.removeItem(at: directoryURL)
  }
}

public enum AppStoreDistributionError: Error, LocalizedError, Equatable {
  case missingBuildSetting(String)
  case invalidBuildNumber(String)
  case buildNumberOverrideFailed(String)
  case commandFailed(stage: String, detail: String)
  case invalidArchive(String)
  case identityMismatch(expected: String, actual: String)

  public var errorDescription: String? {
    switch self {
    case .missingBuildSetting(let key):
      "The Release target does not provide the required \(key) build setting."
    case .invalidBuildNumber(let value):
      "The Release build number \"\(value)\" is not a numeric Apple build number "
        + "that Lys can advance automatically."
    case .buildNumberOverrideFailed(let detail):
      "Lys could not safely prepare the Release build number: \(detail)"
    case .commandFailed(let stage, let detail):
      "\(stage) failed: \(detail)"
    case .invalidArchive(let detail):
      "The archive could not be verified: \(detail)"
    case .identityMismatch(let expected, let actual):
      "The archive identity is \(actual), but the selected App Store app requires \(expected)."
    }
  }
}

public enum AppStoreDistributionSupport {
  public static func temporaryBuildNumberOverride(
    target: LocalDistributionTarget, buildNumber: String
  ) throws -> AppStoreInfoPlistBuildNumberOverride? {
    guard !target.usesGeneratedInfoPlist, let infoPlistFile = target.infoPlistFile else {
      return nil
    }
    let url = infoPlistFile.standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw AppStoreDistributionError.buildNumberOverrideFailed(
        "the Release target's Info.plist file could not be found at \(url.path).")
    }
    let originalData: Data
    do {
      originalData = try Data(contentsOf: url)
    } catch {
      throw AppStoreDistributionError.buildNumberOverrideFailed(
        "the Release target's Info.plist file could not be read (\(error.localizedDescription)).")
    }
    var format = PropertyListSerialization.PropertyListFormat.xml
    guard var plist = try? PropertyListSerialization.propertyList(
      from: originalData, options: [], format: &format) as? [String: Any]
    else {
      throw AppStoreDistributionError.buildNumberOverrideFailed(
        "the Release target's Info.plist file is not a readable property list.")
    }
    plist["CFBundleVersion"] = buildNumber
    let overriddenData: Data
    do {
      overriddenData = try PropertyListSerialization.data(
        fromPropertyList: plist, format: format, options: 0)
    } catch {
      throw AppStoreDistributionError.buildNumberOverrideFailed(
        "the Release target's Info.plist could not be updated (\(error.localizedDescription)).")
    }
    guard overriddenData != originalData else { return nil }
    let originalAttributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
    let originalPermissions = originalAttributes[.posixPermissions] as? NSNumber
    do {
      try overriddenData.write(to: url, options: .atomic)
      if let originalPermissions {
        try FileManager.default.setAttributes(
          [.posixPermissions: originalPermissions], ofItemAtPath: url.path)
      }
    } catch {
      throw AppStoreDistributionError.buildNumberOverrideFailed(
        "the Release target's Info.plist could not be temporarily updated (\(error.localizedDescription)).")
    }
    return .init(
      url: url, originalData: originalData, overriddenData: overriddenData,
      originalPOSIXPermissions: originalPermissions?.intValue)
  }

  public static func archiveCommand(
    xcodebuild: URL, target: LocalDistributionTarget, archivePath: URL, derivedDataPath: URL,
    developerDirectory: URL, authentication: AppStoreDistributionAuthentication? = nil,
    allowProvisioningUpdates: Bool, buildNumberOverride: String? = nil
  ) -> CommandSpec {
    var arguments = [
      target.container.pathExtension == "xcworkspace" ? "-workspace" : "-project",
      target.container.path, "-scheme", target.scheme, "-configuration", "Release",
      "-destination", "generic/platform=iOS", "-archivePath", archivePath.path,
      "-derivedDataPath", derivedDataPath.path, "archive",
    ]
    if let buildNumberOverride {
      arguments += [
        "CURRENT_PROJECT_VERSION=\(buildNumberOverride)",
        "INFOPLIST_KEY_CFBundleVersion=\(buildNumberOverride)",
      ]
    }
    if let teamID = normalizedTeamID(target.developmentTeam) {
      arguments.append("DEVELOPMENT_TEAM=\(teamID)")
    }
    if target.codeSignStyle?.caseInsensitiveCompare("automatic") == .orderedSame {
      arguments.append("CODE_SIGN_STYLE=Automatic")
    }
    appendAuthentication(
      to: &arguments, authentication: authentication,
      allowProvisioningUpdates: allowProvisioningUpdates)
    return .init(
      executable: xcodebuild, arguments: arguments,
      environment: ["DEVELOPER_DIR": developerDirectory.path])
  }

  /// Returns the preferred build number when it is above every uploaded number, otherwise
  /// returns the next numeric build number after Apple's highest uploaded build.
  ///
  /// Apple accepts numeric and period-separated numeric CFBundleVersion values. Lys keeps the
  /// source project unchanged and advances only the archive's build settings. Unsupported local
  /// values return nil so the caller can stop with an actionable preflight message.
  public static func uniqueBuildNumber(preferred: String, existing: [String]) -> String? {
    guard let preferred = NumericBuildNumber(preferred) else { return nil }
    let existingNumbers = existing.compactMap(NumericBuildNumber.init)
    guard let highestExisting = existingNumbers.max(by: {
      NumericBuildNumber.compare($0, $1) == .orderedAscending
    }) else {
      return preferred.value
    }
    switch NumericBuildNumber.compare(preferred, highestExisting) {
    case .orderedDescending:
      return preferred.value
    case .orderedAscending, .orderedSame:
      return highestExisting.incremented().value
    }
  }

  public static func uploadCommand(
    xcodebuild: URL, archivePath: URL, exportPath: URL, exportOptionsPlist: URL,
    developerDirectory: URL, authentication: AppStoreDistributionAuthentication,
    allowProvisioningUpdates: Bool
  ) -> CommandSpec {
    var arguments = [
      "-exportArchive", "-archivePath", archivePath.path, "-exportPath", exportPath.path,
      "-exportOptionsPlist", exportOptionsPlist.path,
    ]
    appendAuthentication(
      to: &arguments, authentication: authentication,
      allowProvisioningUpdates: allowProvisioningUpdates)
    return .init(
      executable: xcodebuild, arguments: arguments,
      environment: ["DEVELOPER_DIR": developerDirectory.path])
  }

  public static func exportOptionsData(
    teamID: String?, internalTestingOnly: Bool, uploadSymbols: Bool = true
  ) throws -> Data {
    var options: [String: Any] = [
      "destination": "upload",
      "manageAppVersionAndBuildNumber": false,
      "method": "app-store-connect",
      "signingStyle": "automatic",
      "testFlightInternalTestingOnly": internalTestingOnly,
      "uploadSymbols": uploadSymbols,
    ]
    if let teamID = normalized(teamID) { options["teamID"] = teamID }
    return try PropertyListSerialization.data(
      fromPropertyList: options, format: .xml, options: 0)
  }

  public static func inspectArchive(at archiveURL: URL) throws -> AppStoreArchiveInspection {
    let infoURL = archiveURL.appending(path: "Info.plist")
    guard let data = try? Data(contentsOf: infoURL),
      let root = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let properties = root["ApplicationProperties"] as? [String: Any]
    else {
      throw AppStoreDistributionError.invalidArchive("Info.plist is missing or unreadable.")
    }
    guard let bundleID = normalized(properties["CFBundleIdentifier"] as? String) else {
      throw AppStoreDistributionError.invalidArchive("CFBundleIdentifier is missing.")
    }
    guard let marketingVersion = normalized(
      properties["CFBundleShortVersionString"] as? String)
    else {
      throw AppStoreDistributionError.invalidArchive(
        "CFBundleShortVersionString is missing.")
    }
    guard let buildNumber = normalized(properties["CFBundleVersion"] as? String) else {
      throw AppStoreDistributionError.invalidArchive("CFBundleVersion is missing.")
    }
    return .init(
      bundleID: bundleID, marketingVersion: marketingVersion, buildNumber: buildNumber,
      signingIdentity: normalized(properties["SigningIdentity"] as? String),
      teamID: normalized(properties["Team"] as? String),
      applicationPath: normalized(properties["ApplicationPath"] as? String),
      architectures: properties["Architectures"] as? [String] ?? [])
  }

  public static func parseSigningIdentities(_ output: String) -> [DistributionSigningIdentity] {
    output.split(separator: "\n").compactMap { line in
      let value = String(line)
      guard let quoteStart = value.firstIndex(of: "\"") else { return nil }
      let suffix = value[value.index(after: quoteStart)...]
      guard let quoteEnd = suffix.firstIndex(of: "\"") else { return nil }
      let name = String(suffix[..<quoteEnd])
      let prefix = value[..<quoteStart].split(whereSeparator: \.isWhitespace)
      guard let fingerprint = prefix.last.map(String.init), fingerprint.count >= 20 else {
        return nil
      }
      return .init(fingerprint: fingerprint, name: name)
    }
  }

  public static func actionableFailureDetail(
    stdout: String, stderr: String, status: Int32
  ) -> String {
    let lines = (stderr + "\n" + stdout)
      .components(separatedBy: .newlines)
      .map(stripANSIEscapes)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let diagnosticTerms = [
      "error:", "requires a development team", "no accounts", "no signing certificate",
      "signing certificate", "provisioning profile", "codesign", "authentication",
    ]
    let diagnostics = unique(
      lines.filter { line in
        let normalized = line.lowercased()
        return diagnosticTerms.contains { normalized.contains($0) }
      })
    if !diagnostics.isEmpty { return diagnostics.suffix(10).joined(separator: "\n") }

    let genericTerms = [
      "** archive failed **", "** export failed **", "the following build commands failed:",
      "archiving workspace", "archiving project", "(1 failure)",
    ]
    let meaningful = unique(
      lines.filter { line in
        let normalized = line.lowercased()
        return !genericTerms.contains { normalized.contains($0) }
      })
    let detail = meaningful.suffix(12).joined(separator: "\n")
    return detail.isEmpty
      ? "xcodebuild exited with status \(status). Open the build log for details."
      : detail
  }

  public static func normalizedTeamID(_ value: String?) -> String? {
    let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    guard value.count == 10,
      value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
    else { return nil }
    return value
  }

  private static func appendAuthentication(
    to arguments: inout [String], authentication: AppStoreDistributionAuthentication?,
    allowProvisioningUpdates: Bool
  ) {
    if let authentication {
      arguments += [
        "-authenticationKeyPath", authentication.privateKeyURL.path,
        "-authenticationKeyID", authentication.keyID,
        "-authenticationKeyIssuerID", authentication.issuerID,
      ]
    }
    if allowProvisioningUpdates { arguments.append("-allowProvisioningUpdates") }
  }

  private static func normalized(_ value: String?) -> String? {
    let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.flatMap { $0.isEmpty ? nil : $0 }
  }

  private static func stripANSIEscapes(_ value: String) -> String {
    value.replacingOccurrences(
      of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  private struct NumericBuildNumber: Sendable {
    let components: [String]

    init?(_ value: String) {
      let pieces = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
      guard !pieces.isEmpty,
        pieces.allSatisfy({ piece in
          !piece.isEmpty
            && piece.unicodeScalars.allSatisfy { scalar in scalar.value >= 48 && scalar.value <= 57 }
        })
      else { return nil }
      components = pieces.map(Self.normalize)
    }

    private init(components: [String]) {
      self.components = components
    }

    var value: String { components.joined(separator: ".") }

    func incremented() -> Self {
      var components = self.components
      components[components.index(before: components.endIndex)] = Self.increment(
        components[components.index(before: components.endIndex)])
      return .init(components: components)
    }

    static func compare(_ lhs: Self, _ rhs: Self) -> ComparisonResult {
      let count = max(lhs.components.count, rhs.components.count)
      for index in 0..<count {
        let left = index < lhs.components.count ? lhs.components[index] : "0"
        let right = index < rhs.components.count ? rhs.components[index] : "0"
        if left.count != right.count {
          return left.count < right.count ? .orderedAscending : .orderedDescending
        }
        if left != right {
          return left < right ? .orderedAscending : .orderedDescending
        }
      }
      return .orderedSame
    }

    private static func normalize(_ value: String) -> String {
      let normalized = value.drop(while: { $0 == "0" })
      return normalized.isEmpty ? "0" : String(normalized)
    }

    private static func increment(_ value: String) -> String {
      var digits = Array(value.utf8)
      var index = digits.count
      while index > 0 {
        index -= 1
        if digits[index] == 57 {
          digits[index] = 48
        } else {
          digits[index] += 1
          return String(decoding: digits, as: UTF8.self)
        }
      }
      return "1" + String(decoding: digits, as: UTF8.self)
    }
  }
}
