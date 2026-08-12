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

  public init(
    container: URL, scheme: String, target: String, bundleID: String, productName: String,
    marketingVersion: String, buildNumber: String, developmentTeam: String? = nil,
    codeSignStyle: String? = nil, codeSignIdentity: String? = nil,
    provisioningProfileSpecifier: String? = nil, entitlementsPath: String? = nil
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
  case commandFailed(stage: String, detail: String)
  case invalidArchive(String)
  case identityMismatch(expected: String, actual: String)

  public var errorDescription: String? {
    switch self {
    case .missingBuildSetting(let key):
      "The Release target does not provide the required \(key) build setting."
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
  public static func archiveCommand(
    xcodebuild: URL, target: LocalDistributionTarget, archivePath: URL, derivedDataPath: URL,
    developerDirectory: URL, authentication: AppStoreDistributionAuthentication? = nil,
    allowProvisioningUpdates: Bool
  ) -> CommandSpec {
    var arguments = [
      target.container.pathExtension == "xcworkspace" ? "-workspace" : "-project",
      target.container.path, "-scheme", target.scheme, "-configuration", "Release",
      "-destination", "generic/platform=iOS", "-archivePath", archivePath.path,
      "-derivedDataPath", derivedDataPath.path, "archive",
    ]
    appendAuthentication(
      to: &arguments, authentication: authentication,
      allowProvisioningUpdates: allowProvisioningUpdates)
    return .init(
      executable: xcodebuild, arguments: arguments,
      environment: ["DEVELOPER_DIR": developerDirectory.path])
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
}
