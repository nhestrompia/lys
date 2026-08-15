import Foundation
import Testing

@testable import IOSDevCore

@Test func appStoreDistributionCommandsPreservePathsAndExplicitSigningAuthority() throws {
  let target = LocalDistributionTarget(
    container: URL(fileURLWithPath: "/tmp/Client App;$(touch nope).xcworkspace"),
    scheme: "Release App; echo nope", target: "Release App", bundleID: "com.example.app",
    productName: "Release App", marketingVersion: "2.4", buildNumber: "42",
    developmentTeam: "TEAM123ABC", codeSignStyle: "Automatic")
  let authentication = AppStoreDistributionAuthentication(
    privateKeyURL: URL(fileURLWithPath: "/tmp/private key/AuthKey_TEST.p8"), keyID: "KEY123",
    issuerID: "issuer-123")
  let archive = AppStoreDistributionSupport.archiveCommand(
    xcodebuild: URL(fileURLWithPath: "/Applications/Xcode.app/usr/bin/xcodebuild"),
    target: target, archivePath: URL(fileURLWithPath: "/tmp/job/App archive.xcarchive"),
    derivedDataPath: URL(fileURLWithPath: "/tmp/job/Derived Data"),
    developerDirectory: URL(fileURLWithPath: "/Applications/Xcode.app/Developer"),
    authentication: authentication, allowProvisioningUpdates: true)

  #expect(archive.arguments[0] == "-workspace")
  #expect(archive.arguments[1] == "/tmp/Client App;$(touch nope).xcworkspace")
  #expect(archive.arguments.contains("Release App; echo nope"))
  #expect(archive.arguments.contains("generic/platform=iOS"))
  #expect(archive.arguments.contains("/tmp/job/App archive.xcarchive"))
  #expect(archive.arguments.contains("/tmp/private key/AuthKey_TEST.p8"))
  #expect(archive.arguments.contains("-allowProvisioningUpdates"))
  #expect(archive.arguments.contains("DEVELOPMENT_TEAM=TEAM123ABC"))
  #expect(archive.arguments.contains("CODE_SIGN_STYLE=Automatic"))

  let upload = AppStoreDistributionSupport.uploadCommand(
    xcodebuild: archive.executable,
    archivePath: URL(fileURLWithPath: "/tmp/job/App archive.xcarchive"),
    exportPath: URL(fileURLWithPath: "/tmp/job/Upload"),
    exportOptionsPlist: URL(fileURLWithPath: "/tmp/job/ExportOptions.plist"),
    developerDirectory: URL(fileURLWithPath: "/Applications/Xcode.app/Developer"),
    authentication: authentication, allowProvisioningUpdates: false)
  #expect(upload.arguments.first == "-exportArchive")
  #expect(!upload.arguments.contains("-allowProvisioningUpdates"))
  #expect(upload.arguments.contains("-authenticationKeyIssuerID"))
}

@Test func appStoreArchiveCommandCanOverrideOnlyTheArchivedBuildNumber() {
  let target = LocalDistributionTarget(
    container: URL(fileURLWithPath: "/tmp/Release.xcodeproj"), scheme: "Release",
    target: "Release", bundleID: "com.example.app", productName: "Release",
    marketingVersion: "2.4", buildNumber: "7")
  let command = AppStoreDistributionSupport.archiveCommand(
    xcodebuild: URL(fileURLWithPath: "/usr/bin/xcodebuild"), target: target,
    archivePath: URL(fileURLWithPath: "/tmp/App.xcarchive"),
    derivedDataPath: URL(fileURLWithPath: "/tmp/DerivedData"),
    developerDirectory: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
    allowProvisioningUpdates: false, buildNumberOverride: "8")

  #expect(command.arguments.contains("CURRENT_PROJECT_VERSION=8"))
  #expect(command.arguments.contains("INFOPLIST_KEY_CFBundleVersion=8"))
}

@Test func appStoreUniqueBuildNumberAdvancesOnlyWhenNeeded() {
  #expect(
    AppStoreDistributionSupport.uniqueBuildNumber(
      preferred: "42", existing: ["40", "41"]) == "42")
  #expect(
    AppStoreDistributionSupport.uniqueBuildNumber(
      preferred: "42", existing: ["40", "42"]) == "43")
  #expect(
    AppStoreDistributionSupport.uniqueBuildNumber(
      preferred: "1.0", existing: ["1.0", "1.0.3"]) == "1.0.4")
  #expect(
    AppStoreDistributionSupport.uniqueBuildNumber(
      preferred: "42", existing: ["000042"]) == "43")
  #expect(
    AppStoreDistributionSupport.uniqueBuildNumber(
      preferred: "build-42", existing: ["build-41"]) == nil)
}

@Test func appStoreExportOptionsKeepReviewedBuildNumberAndInternalRestriction() throws {
  let data = try AppStoreDistributionSupport.exportOptionsData(
    teamID: "TEAM123ABC", internalTestingOnly: true, uploadSymbols: true)
  let plist = try #require(
    PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  #expect(plist["method"] as? String == "app-store-connect")
  #expect(plist["destination"] as? String == "upload")
  #expect(plist["manageAppVersionAndBuildNumber"] as? Bool == false)
  #expect(plist["testFlightInternalTestingOnly"] as? Bool == true)
  #expect(plist["uploadSymbols"] as? Bool == true)
  #expect(plist["teamID"] as? String == "TEAM123ABC")
  #expect(plist["signingStyle"] as? String == "automatic")
}

@Test func appStoreTeamIDNormalizationRejectsIssuerIDsAndUnsafeOverrides() {
  #expect(AppStoreDistributionSupport.normalizedTeamID(" abc123defg ") == "ABC123DEFG")
  #expect(AppStoreDistributionSupport.normalizedTeamID("issuer-123") == nil)
  #expect(AppStoreDistributionSupport.normalizedTeamID("TEAM=12345") == nil)
}

@Test func appStoreArchiveInspectionReadsTheIdentityXcodeActuallyArchived() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
    .appending(path: "App.xcarchive")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let plist: [String: Any] = [
    "ApplicationProperties": [
      "ApplicationPath": "Applications/Release App.app",
      "Architectures": ["arm64"],
      "CFBundleIdentifier": "com.example.app",
      "CFBundleShortVersionString": "2.4",
      "CFBundleVersion": "42",
      "SigningIdentity": "Apple Distribution: Example, Inc. (TEAM123)",
      "Team": "TEAM123",
    ]
  ]
  let data = try PropertyListSerialization.data(
    fromPropertyList: plist, format: .xml, options: 0)
  try data.write(to: root.appending(path: "Info.plist"))

  let inspection = try AppStoreDistributionSupport.inspectArchive(at: root)
  #expect(inspection.bundleID == "com.example.app")
  #expect(inspection.marketingVersion == "2.4")
  #expect(inspection.buildNumber == "42")
  #expect(inspection.teamID == "TEAM123")
  #expect(inspection.architectures == ["arm64"])
}

@Test func appStoreSigningIdentityParserDistinguishesDistributionCertificates() {
  let identities = AppStoreDistributionSupport.parseSigningIdentities(
    """
      1) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Ada (TEAM123)"
      2) FEDCBA9876543210FEDCBA9876543210FEDCBA98 "Apple Distribution: Ada (TEAM123)"
         2 valid identities found
    """)
  #expect(identities.count == 2)
  #expect(identities.filter(\.isDistributionIdentity).map(\.fingerprint) == [
    "FEDCBA9876543210FEDCBA9876543210FEDCBA98"
  ])
}

@Test func releaseDiscoveryPrefersTheInfoPlistVersionXcodeActuallyArchives() {
  let versions = ToolchainDiscovery.effectiveBundleVersions(
    buildSettings: [
      "MARKETING_VERSION": "1.0",
      "CURRENT_PROJECT_VERSION": "1",
    ],
    infoPlist: [
      "CFBundleShortVersionString": "1.0.17",
      "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    ])

  #expect(versions.marketingVersion == "1.0.17")
  #expect(versions.buildNumber == "1")
}

@Test func releaseDiscoveryFallsBackToBuildSettingsWithoutAnInfoPlist() {
  let versions = ToolchainDiscovery.effectiveBundleVersions(
    buildSettings: [
      "MARKETING_VERSION": "2.4",
      "CURRENT_PROJECT_VERSION": "42",
    ], infoPlist: nil)

  #expect(versions.marketingVersion == "2.4")
  #expect(versions.buildNumber == "42")
}

@Test func releaseDiscoveryLoadsTheResolvedSourceInfoPlist() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let appDirectory = root.appending(path: "ReleaseApp", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let data = try PropertyListSerialization.data(
    fromPropertyList: [
      "CFBundleShortVersionString": "1.0.17",
      "CFBundleVersion": "9",
    ], format: .xml, options: 0)
  try data.write(to: appDirectory.appending(path: "Info.plist"))

  let versions = ToolchainDiscovery.effectiveBundleVersions(
    buildSettings: [
      "SRCROOT": root.path,
      "INFOPLIST_FILE": "ReleaseApp/Info.plist",
      "MARKETING_VERSION": "1.0",
      "CURRENT_PROJECT_VERSION": "1",
    ],
    container: root.appending(path: "ReleaseApp.xcodeproj"))

  #expect(versions.marketingVersion == "1.0.17")
  #expect(versions.buildNumber == "9")
}

@Test func appStoreDistributionFailurePrefersActionableSigningDiagnostics() {
  let detail = AppStoreDistributionSupport.actionableFailureDetail(
    stdout: """
      The following build commands failed:
      Archiving workspace Ellinix with scheme Ellinix
      error: Signing for "Ellinix" requires a development team. Select a development team in the Signing & Capabilities editor.
      (1 failure)
      """,
    stderr: "** ARCHIVE FAILED **", status: 65)
  #expect(detail.contains("requires a development team"))
  #expect(!detail.contains("ARCHIVE FAILED"))
  #expect(!detail.contains("Archiving workspace"))
}

@Test func appStoreTemporaryCredentialIsOwnerOnlyAndRecoverablyRemoved() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let credential = try AppStoreTemporaryCredential.create(
    privateKey: Data("private".utf8), keyID: "KEY123", in: root)
  let directoryMode = try #require(
    FileManager.default.attributesOfItem(atPath: credential.directoryURL.path)[.posixPermissions]
      as? NSNumber)
  let keyMode = try #require(
    FileManager.default.attributesOfItem(atPath: credential.privateKeyURL.path)[.posixPermissions]
      as? NSNumber)
  #expect(directoryMode.intValue & 0o777 == 0o700)
  #expect(keyMode.intValue & 0o777 == 0o600)
  #expect(try Data(contentsOf: credential.privateKeyURL) == Data("private".utf8))
  try credential.remove()
  #expect(!FileManager.default.fileExists(atPath: credential.directoryURL.path))
  try credential.remove()
}
