import Foundation
import Testing

@testable import IOSDevCore

@Test func appStoreDistributionCommandsPreservePathsAndExplicitSigningAuthority() throws {
  let target = LocalDistributionTarget(
    container: URL(fileURLWithPath: "/tmp/Client App;$(touch nope).xcworkspace"),
    scheme: "Release App; echo nope", target: "Release App", bundleID: "com.example.app",
    productName: "Release App", marketingVersion: "2.4", buildNumber: "42",
    developmentTeam: "TEAM123", codeSignStyle: "Automatic")
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

@Test func appStoreExportOptionsKeepReviewedBuildNumberAndInternalRestriction() throws {
  let data = try AppStoreDistributionSupport.exportOptionsData(
    teamID: "TEAM123", internalTestingOnly: true, uploadSymbols: true)
  let plist = try #require(
    PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  #expect(plist["method"] as? String == "app-store-connect")
  #expect(plist["destination"] as? String == "upload")
  #expect(plist["manageAppVersionAndBuildNumber"] as? Bool == false)
  #expect(plist["testFlightInternalTestingOnly"] as? Bool == true)
  #expect(plist["uploadSymbols"] as? Bool == true)
  #expect(plist["teamID"] as? String == "TEAM123")
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
