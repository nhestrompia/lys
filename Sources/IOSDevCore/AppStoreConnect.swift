import CryptoKit
import Foundation
@preconcurrency import Security

public enum AppStoreConnectKeyKind: String, Codable, CaseIterable, Sendable {
  case team
  case individual
}

public struct AppStoreConnection: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var label: String
  public var keyID: String
  public var issuerID: String?
  public var keyKind: AppStoreConnectKeyKind
  public var createdAt: Date
  public var validatedAt: Date

  public init(
    id: UUID = UUID(), label: String, keyID: String, issuerID: String?,
    keyKind: AppStoreConnectKeyKind = .team, createdAt: Date = Date(),
    validatedAt: Date = Date()
  ) {
    self.id = id
    self.label = label
    self.keyID = keyID
    self.issuerID = issuerID
    self.keyKind = keyKind
    self.createdAt = createdAt
    self.validatedAt = validatedAt
  }
}

public struct AppStoreApp: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var name: String
  public var bundleID: String
  public var sku: String
  public var primaryLocale: String

  public init(
    id: String, name: String, bundleID: String, sku: String, primaryLocale: String
  ) {
    self.id = id
    self.name = name
    self.bundleID = bundleID
    self.sku = sku
    self.primaryLocale = primaryLocale
  }
}

public struct AppStoreVersion: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var platform: String
  public var versionString: String
  public var state: String
  public var releaseType: String?
  public var earliestReleaseDate: Date?
  public var createdDate: Date?
  public var downloadable: Bool?
  public var buildID: String?

  public init(
    id: String, platform: String, versionString: String, state: String,
    releaseType: String? = nil, earliestReleaseDate: Date? = nil, createdDate: Date? = nil,
    downloadable: Bool? = nil, buildID: String? = nil
  ) {
    self.id = id
    self.platform = platform
    self.versionString = versionString
    self.state = state
    self.releaseType = releaseType
    self.earliestReleaseDate = earliestReleaseDate
    self.createdDate = createdDate
    self.downloadable = downloadable
    self.buildID = buildID
  }
}

public struct AppStoreBuild: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var version: String
  public var marketingVersion: String?
  public var uploadedDate: Date?
  public var expirationDate: Date?
  public var expired: Bool
  public var minimumOSVersion: String?
  public var processingState: String
  public var audienceType: String?
  public var usesNonExemptEncryption: Bool?

  public init(
    id: String, version: String, marketingVersion: String? = nil,
    uploadedDate: Date? = nil, expirationDate: Date? = nil, expired: Bool = false,
    minimumOSVersion: String? = nil, processingState: String,
    audienceType: String? = nil, usesNonExemptEncryption: Bool? = nil
  ) {
    self.id = id
    self.version = version
    self.marketingVersion = marketingVersion
    self.uploadedDate = uploadedDate
    self.expirationDate = expirationDate
    self.expired = expired
    self.minimumOSVersion = minimumOSVersion
    self.processingState = processingState
    self.audienceType = audienceType
    self.usesNonExemptEncryption = usesNonExemptEncryption
  }
}

public struct AppStoreBetaGroup: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var name: String
  public var isInternal: Bool
  public var hasAccessToAllBuilds: Bool
  public var publicLinkEnabled: Bool
  public var feedbackEnabled: Bool
  public var testerCount: Int?
  public var testers: [AppStoreBetaTester]

  public init(
    id: String, name: String, isInternal: Bool, hasAccessToAllBuilds: Bool,
    publicLinkEnabled: Bool, feedbackEnabled: Bool, testerCount: Int? = nil,
    testers: [AppStoreBetaTester] = []
  ) {
    self.id = id
    self.name = name
    self.isInternal = isInternal
    self.hasAccessToAllBuilds = hasAccessToAllBuilds
    self.publicLinkEnabled = publicLinkEnabled
    self.feedbackEnabled = feedbackEnabled
    self.testerCount = testerCount
    self.testers = testers
  }
}

public struct AppStoreBetaTester: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var firstName: String?
  public var lastName: String?
  public var email: String
  public var inviteType: String?
  public var state: String?

  public init(
    id: String, firstName: String? = nil, lastName: String? = nil, email: String,
    inviteType: String? = nil, state: String? = nil
  ) {
    self.id = id
    self.firstName = firstName
    self.lastName = lastName
    self.email = email
    self.inviteType = inviteType
    self.state = state
  }

  public var name: String? {
    [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }.joined(separator: " ").nilIfEmpty
  }
}

public struct AppStoreVersionLocalization: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var locale: String
  public var whatsNew: String?
  public var promotionalText: String?

  public init(id: String, locale: String, whatsNew: String?, promotionalText: String?) {
    self.id = id
    self.locale = locale
    self.whatsNew = whatsNew
    self.promotionalText = promotionalText
  }
}

public struct AppStoreScreenshot: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var fileName: String
  public var fileSize: Int?
  public var width: Int?
  public var height: Int?
  public var templateURL: String?
  public var deliveryState: String?

  public init(
    id: String, fileName: String, fileSize: Int? = nil, width: Int? = nil,
    height: Int? = nil, templateURL: String? = nil, deliveryState: String? = nil
  ) {
    self.id = id
    self.fileName = fileName
    self.fileSize = fileSize
    self.width = width
    self.height = height
    self.templateURL = templateURL
    self.deliveryState = deliveryState
  }

  public var downloadURL: URL? {
    guard var value = templateURL else { return nil }
    value = value.replacingOccurrences(of: "{w}", with: String(width ?? 900))
    value = value.replacingOccurrences(of: "{h}", with: String(height ?? 1_950))
    value = value.replacingOccurrences(of: "{f}", with: "png")
    value = value.replacingOccurrences(of: "{+dpr}", with: "")
    value = value.replacingOccurrences(of: "{dpr}", with: "1")
    value = value.replacingOccurrences(of: "{c}", with: "")
    return URL(string: value)
  }
}

public struct AppStoreScreenshotSet: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var locale: String
  public var displayType: String
  public var screenshots: [AppStoreScreenshot]

  public init(
    id: String, locale: String, displayType: String, screenshots: [AppStoreScreenshot]
  ) {
    self.id = id
    self.locale = locale
    self.displayType = displayType
    self.screenshots = screenshots
  }
}

public enum AppStoreFeedbackKind: String, Codable, Hashable, Sendable {
  case screenshot
  case crash
}

public struct AppStoreFeedback: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var kind: AppStoreFeedbackKind
  public var createdDate: Date?
  public var comment: String?
  public var deviceModel: String?
  public var osVersion: String?
  public var buildBundleID: String?
  public var imageURL: URL?
  public var buildID: String?

  public init(
    id: String, kind: AppStoreFeedbackKind, createdDate: Date? = nil,
    comment: String? = nil, deviceModel: String? = nil, osVersion: String? = nil,
    buildBundleID: String? = nil, imageURL: URL? = nil, buildID: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.createdDate = createdDate
    self.comment = comment
    self.deviceModel = deviceModel
    self.osVersion = osVersion
    self.buildBundleID = buildBundleID
    self.imageURL = imageURL
    self.buildID = buildID
  }
}

public enum AppStoreConnectionPhase: String, Codable, Sendable {
  case disconnected
  case connecting
  case refreshing
  case connected
  case failed
}

public enum AppStoreConnectError: Error, LocalizedError, Sendable {
  case invalidPrivateKey
  case invalidConnection(String)
  case invalidResponse
  case unsafeRedirect(String)
  case api(status: Int, message: String)
  case keychain(operation: String, status: OSStatus)

  public var errorDescription: String? {
    switch self {
    case .invalidPrivateKey:
      return
        "The selected file is not a valid App Store Connect P-256 private key. Select the original .p8 file downloaded from Apple."
    case .invalidConnection(let message): return message
    case .invalidResponse:
      return "App Store Connect returned a response Lys could not understand."
    case .unsafeRedirect(let host):
      return "App Store Connect redirected the request to an unexpected host: \(host)"
    case .api(let status, let message):
      return "App Store Connect request failed (HTTP \(status)): \(message)"
    case .keychain(let operation, let status):
      let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
      return "Could not \(operation) the App Store Connect key in Keychain: \(detail)"
    }
  }
}

public enum AppStoreCredentialStore {
  public static let service = "dev.lys.app-store-connect"

  public static func validate(privateKeyPEM: Data) throws {
    guard let pem = String(data: privateKeyPEM, encoding: .utf8),
      (try? P256.Signing.PrivateKey(pemRepresentation: pem)) != nil
    else { throw AppStoreConnectError.invalidPrivateKey }
  }

  public static func read(connectionID: UUID) throws -> Data? {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: connectionID.uuidString,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ] as CFDictionary,
      &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw AppStoreConnectError.keychain(operation: "read", status: status)
    }
    return data
  }

  public static func write(_ privateKeyPEM: Data, connectionID: UUID) throws {
    try validate(privateKeyPEM: privateKeyPEM)
    let lookup =
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: connectionID.uuidString,
      ] as CFDictionary
    let attributes = [kSecValueData as String: privateKeyPEM] as CFDictionary
    let updated = SecItemUpdate(lookup, attributes)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else {
      throw AppStoreConnectError.keychain(operation: "update", status: updated)
    }
    let inserted = SecItemAdd(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: connectionID.uuidString,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecValueData as String: privateKeyPEM,
      ] as CFDictionary,
      nil)
    guard inserted == errSecSuccess else {
      throw AppStoreConnectError.keychain(operation: "save", status: inserted)
    }
  }

  public static func delete(connectionID: UUID) throws {
    let status = SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: connectionID.uuidString,
      ] as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AppStoreConnectError.keychain(operation: "remove", status: status)
    }
  }
}

public actor AppStoreCredentialSession {
  public typealias Loader = @Sendable (UUID) throws -> Data?

  private var cachedKeys: [UUID: Data] = [:]
  private let loader: Loader

  public init(
    loader: @escaping Loader = { connectionID in
      try AppStoreCredentialStore.read(connectionID: connectionID)
    }
  ) {
    self.loader = loader
  }

  public func privateKey(for connectionID: UUID) throws -> Data {
    if let cached = cachedKeys[connectionID] { return cached }
    guard let loaded = try loader(connectionID) else {
      throw AppStoreConnectError.invalidConnection(
        "The saved connection metadata exists, but its private key is missing from Keychain. Reconnect the account."
      )
    }
    try AppStoreCredentialStore.validate(privateKeyPEM: loaded)
    cachedKeys[connectionID] = loaded
    return loaded
  }

  public func cache(_ privateKey: Data, for connectionID: UUID) throws {
    try AppStoreCredentialStore.validate(privateKeyPEM: privateKey)
    cachedKeys[connectionID] = privateKey
  }

  public func remove(connectionID: UUID) {
    cachedKeys.removeValue(forKey: connectionID)
  }

  public func removeAll() {
    cachedKeys.removeAll(keepingCapacity: false)
  }
}

public struct AppStoreConnectTokenSigner: Sendable {
  public var connection: AppStoreConnection
  private let privateKeyPEM: Data

  public init(connection: AppStoreConnection, privateKeyPEM: Data) throws {
    try AppStoreCredentialStore.validate(privateKeyPEM: privateKeyPEM)
    self.connection = connection
    self.privateKeyPEM = privateKeyPEM
  }

  public func token(
    now: Date = Date(), lifetime: TimeInterval = 15 * 60, scope: [String]? = nil
  ) throws -> String {
    guard lifetime > 0, lifetime <= 20 * 60 else {
      throw AppStoreConnectError.invalidConnection(
        "App Store Connect tokens must expire within 20 minutes.")
    }
    let keyID = connection.keyID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyID.isEmpty else {
      throw AppStoreConnectError.invalidConnection("A Key ID is required.")
    }
    let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
    var payload: [String: Any] = [
      "iat": Int(now.timeIntervalSince1970),
      "exp": Int(now.addingTimeInterval(lifetime).timeIntervalSince1970),
      "aud": "appstoreconnect-v1",
    ]
    switch connection.keyKind {
    case .team:
      guard let issuer = connection.issuerID?.trimmingCharacters(in: .whitespacesAndNewlines),
        !issuer.isEmpty
      else {
        throw AppStoreConnectError.invalidConnection(
          "An Issuer ID is required for a team API key.")
      }
      payload["iss"] = issuer
    case .individual:
      payload["sub"] = "user"
    }
    if let scope, !scope.isEmpty { payload["scope"] = scope }

    let encodedHeader = try Self.base64URL(Self.jsonData(header))
    let encodedPayload = try Self.base64URL(Self.jsonData(payload))
    let signingInput = "\(encodedHeader).\(encodedPayload)"
    guard let pem = String(data: privateKeyPEM, encoding: .utf8) else {
      throw AppStoreConnectError.invalidPrivateKey
    }
    let key: P256.Signing.PrivateKey
    do {
      key = try P256.Signing.PrivateKey(pemRepresentation: pem)
    } catch {
      throw AppStoreConnectError.invalidPrivateKey
    }
    let signature = try key.signature(for: Data(signingInput.utf8))
    return "\(signingInput).\(Self.base64URL(signature.rawRepresentation))"
  }

  private static func jsonData(_ value: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

public actor AppStoreConnectClient {
  private let signer: AppStoreConnectTokenSigner
  private let session: URLSession
  private let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!

  public init(
    connection: AppStoreConnection, privateKeyPEM: Data,
    session: URLSession = .shared
  ) throws {
    signer = try AppStoreConnectTokenSigner(
      connection: connection, privateKeyPEM: privateKeyPEM)
    self.session = session
  }

  public func listApps(bundleID: String? = nil) async throws -> [AppStoreApp] {
    var components = URLComponents(
      url: baseURL.appending(path: "v1/apps"), resolvingAgainstBaseURL: false)!
    var query = [
      URLQueryItem(name: "fields[apps]", value: "name,bundleId,sku,primaryLocale"),
      URLQueryItem(name: "limit", value: "200"),
      URLQueryItem(name: "sort", value: "name"),
    ]
    if let bundleID, !bundleID.isEmpty {
      query.append(URLQueryItem(name: "filter[bundleId]", value: bundleID))
    }
    components.queryItems = query
    guard var nextURL = components.url else { throw AppStoreConnectError.invalidResponse }
    var apps: [AppStoreApp] = []
    var pageCount = 0
    while true {
      guard nextURL.scheme == "https", nextURL.host == baseURL.host else {
        throw AppStoreConnectError.unsafeRedirect(nextURL.host ?? "unknown")
      }
      let document: AppsDocument = try await get(nextURL)
      apps.append(contentsOf: document.data.map(\.app))
      pageCount += 1
      guard let following = document.links?.next else { break }
      guard pageCount < 100 else {
        throw AppStoreConnectError.invalidConnection(
          "App Store Connect returned more app pages than Lys can safely load in one refresh.")
      }
      nextURL = following
    }
    return apps
  }

  public func listAppStoreVersions(appID: String) async throws -> [AppStoreVersion] {
    let url = try endpoint(
      "v1/apps/\(safeResourceID(appID))/appStoreVersions",
      query: [
        .init(name: "filter[platform]", value: "IOS"),
        .init(
          name: "fields[appStoreVersions]",
          value:
            "platform,versionString,appVersionState,releaseType,earliestReleaseDate,downloadable,createdDate,build"
        ),
        .init(name: "limit", value: "200"),
      ])
    let resources: [AppStoreVersionResource] = try await getAll(url)
    return resources.map(\.version).sorted {
      ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
    }
  }

  public func listBuilds(appID: String) async throws -> [AppStoreBuild] {
    let safeAppID = try safeResourceID(appID)
    let buildURL = try endpoint(
      "v1/apps/\(safeAppID)/builds",
      query: [
        .init(
          name: "fields[builds]",
          value:
            "version,uploadedDate,expirationDate,expired,minOsVersion,processingState,buildAudienceType,usesNonExemptEncryption,preReleaseVersion"
        ),
        .init(name: "limit", value: "200"),
      ])
    let prereleaseURL = try endpoint(
      "v1/apps/\(safeAppID)/preReleaseVersions",
      query: [
        .init(name: "fields[preReleaseVersions]", value: "version,platform"),
        .init(name: "limit", value: "200"),
      ])
    let buildResources: [BuildResource] = try await getAll(buildURL)
    let prereleaseResources: [PreReleaseVersionResource] = try await getAll(prereleaseURL)
    let marketingVersions = Dictionary(
      uniqueKeysWithValues: prereleaseResources.map { ($0.id, $0.attributes?.version) })
    return buildResources.map { $0.build(marketingVersions: marketingVersions) }.sorted {
      ($0.uploadedDate ?? .distantPast) > ($1.uploadedDate ?? .distantPast)
    }
  }

  public func listBetaGroups(appID: String) async throws -> [AppStoreBetaGroup] {
    let url = try endpoint(
      "v1/betaGroups",
      query: [
        .init(name: "filter[app]", value: try safeResourceID(appID)),
        .init(
          name: "fields[betaGroups]",
          value:
            "name,isInternalGroup,hasAccessToAllBuilds,publicLinkEnabled,feedbackEnabled,betaTesters"
        ),
        .init(name: "fields[betaTesters]", value: "state"),
        .init(name: "include", value: "betaTesters"),
        .init(name: "limit[betaTesters]", value: "1"),
        .init(name: "limit", value: "200"),
        .init(name: "sort", value: "name"),
      ])
    let resources: [BetaGroupResource] = try await getAll(url)
    var groups: [AppStoreBetaGroup] = []
    for resource in resources {
      var group = resource.group
      group.testers = try await listBetaTesters(groupID: group.id)
      group.testerCount = group.testers.count
      groups.append(group)
    }
    return groups
  }

  public func listBetaTesters(groupID: String) async throws -> [AppStoreBetaTester] {
    let url = try endpoint(
      "v1/betaGroups/\(safeResourceID(groupID))/betaTesters",
      query: [
        .init(name: "fields[betaTesters]", value: "firstName,lastName,email,inviteType,state"),
        .init(name: "limit", value: "200"),
        .init(name: "sort", value: "email"),
      ])
    let resources: [BetaTesterResource] = try await getAll(url)
    return resources.map(\.tester)
  }

  @discardableResult
  public func addBetaTester(
    email: String, firstName: String? = nil, lastName: String? = nil, groupID: String
  ) async throws -> AppStoreBetaTester {
    let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedEmail.contains("@"), !normalizedEmail.contains(where: { $0.isWhitespace }) else {
      throw AppStoreConnectError.invalidConnection("Enter a valid tester email address.")
    }
    let request = BetaTesterCreateRequest(
      data: .init(
        type: "betaTesters",
        attributes: .init(
          firstName: firstName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
          lastName: lastName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
          email: normalizedEmail),
        relationships: .init(
          betaGroups: .init(data: [.init(type: "betaGroups", id: try safeResourceID(groupID))]))))
    let response: BetaTesterDocument = try await send(
      try endpoint("v1/betaTesters", query: []), method: "POST", body: request)
    return response.data.tester
  }

  public func removeBetaTester(_ testerID: String, fromGroup groupID: String) async throws {
    let request = RelationshipLinkagesRequest(
      data: [.init(type: "betaTesters", id: try safeResourceID(testerID))])
    try await sendWithoutResponse(
      try endpoint(
        "v1/betaGroups/\(safeResourceID(groupID))/relationships/betaTesters", query: []),
      method: "DELETE", body: request)
  }

  public func listVersionLocalizations(versionID: String) async throws
    -> [AppStoreVersionLocalization]
  {
    let url = try endpoint(
      "v1/appStoreVersions/\(safeResourceID(versionID))/appStoreVersionLocalizations",
      query: [
        .init(
          name: "fields[appStoreVersionLocalizations]",
          value: "locale,whatsNew,promotionalText"),
        .init(name: "limit", value: "200"),
      ])
    let resources: [VersionLocalizationResource] = try await getAll(url)
    return resources.map(\.localization).sorted { $0.locale < $1.locale }
  }

  public func listScreenshotSets(
    versionID: String, preferredLocale: String? = nil
  ) async throws -> [AppStoreScreenshotSet] {
    var localizations = try await listVersionLocalizations(versionID: versionID)
    if let preferredLocale,
      localizations.contains(where: { $0.locale.caseInsensitiveCompare(preferredLocale) == .orderedSame })
    {
      localizations.sort {
        if $0.locale.caseInsensitiveCompare(preferredLocale) == .orderedSame { return true }
        if $1.locale.caseInsensitiveCompare(preferredLocale) == .orderedSame { return false }
        return $0.locale < $1.locale
      }
    }
    var result: [AppStoreScreenshotSet] = []
    for localization in localizations {
      let setURL = try endpoint(
        "v1/appStoreVersionLocalizations/\(safeResourceID(localization.id))/appScreenshotSets",
        query: [
          .init(name: "fields[appScreenshotSets]", value: "screenshotDisplayType"),
          .init(name: "limit", value: "200"),
        ])
      let sets: [ScreenshotSetResource] = try await getAll(setURL)
      for set in sets {
        let screenshotURL = try endpoint(
          "v1/appScreenshotSets/\(safeResourceID(set.id))/appScreenshots",
          query: [
            .init(
              name: "fields[appScreenshots]",
              value: "fileSize,fileName,imageAsset,assetDeliveryState"),
            .init(name: "limit", value: "200"),
          ])
        let screenshots: [ScreenshotResource] = try await getAll(screenshotURL)
        result.append(
          .init(
            id: set.id, locale: localization.locale,
            displayType: set.attributes?.screenshotDisplayType ?? "UNKNOWN",
            screenshots: screenshots.map(\.screenshot)))
      }
    }
    return result
  }

  public func listScreenshotFeedback(appID: String) async throws -> [AppStoreFeedback] {
    let url = try endpoint(
      "v1/apps/\(safeResourceID(appID))/betaFeedbackScreenshotSubmissions",
      query: [
        .init(
          name: "fields[betaFeedbackScreenshotSubmissions]",
          value:
            "createdDate,comment,deviceModel,osVersion,buildBundleId,screenshots,build"),
        .init(name: "filter[appPlatform]", value: "IOS"),
        .init(name: "sort", value: "-createdDate"),
        .init(name: "limit", value: "200"),
      ])
    let resources: [ScreenshotFeedbackResource] = try await getAll(url)
    return resources.map(\.feedback)
  }

  @discardableResult
  public func uploadScreenshot(
    data: Data, fileName: String, screenshotSetID: String
  ) async throws -> AppStoreScreenshot {
    guard !data.isEmpty else {
      throw AppStoreConnectError.invalidConnection("The selected screenshot file is empty.")
    }
    let reservation = ScreenshotCreateRequest(
      data: .init(
        type: "appScreenshots", attributes: .init(fileSize: data.count, fileName: fileName),
        relationships: .init(
          appScreenshotSet: .init(
            data: .init(type: "appScreenshotSets", id: try safeResourceID(screenshotSetID))))))
    let created: ScreenshotDocument = try await send(
      try endpoint("v1/appScreenshots", query: []), method: "POST", body: reservation)
    do {
      for operation in created.data.attributes?.uploadOperations ?? [] {
        try await performUpload(operation, source: data)
      }
      let digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
      let commit = ScreenshotUpdateRequest(
        data: .init(
          type: "appScreenshots", id: created.data.id,
          attributes: .init(sourceFileChecksum: digest, uploaded: true)))
      let committed: ScreenshotDocument = try await send(
        try endpoint("v1/appScreenshots/\(safeResourceID(created.data.id))", query: []),
        method: "PATCH", body: commit)
      return committed.data.screenshot
    } catch {
      try? await deleteScreenshot(id: created.data.id)
      throw error
    }
  }

  public func deleteScreenshot(id: String) async throws {
    try await sendWithoutResponse(
      try endpoint("v1/appScreenshots/\(safeResourceID(id))", query: []),
      method: "DELETE", body: Optional<RelationshipLinkagesRequest>.none)
  }

  public func listCrashFeedback(appID: String) async throws -> [AppStoreFeedback] {
    let url = try endpoint(
      "v1/apps/\(safeResourceID(appID))/betaFeedbackCrashSubmissions",
      query: [
        .init(
          name: "fields[betaFeedbackCrashSubmissions]",
          value: "createdDate,comment,deviceModel,osVersion,buildBundleId,build"),
        .init(name: "filter[appPlatform]", value: "IOS"),
        .init(name: "sort", value: "-createdDate"),
        .init(name: "limit", value: "200"),
      ])
    let resources: [CrashFeedbackResource] = try await getAll(url)
    return resources.map(\.feedback)
  }

  private func endpoint(_ path: String, query: [URLQueryItem]) throws -> URL {
    var components = URLComponents(
      url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
    components?.queryItems = query
    guard let url = components?.url else { throw AppStoreConnectError.invalidResponse }
    return url
  }

  private func safeResourceID(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, !normalized.contains("/"), !normalized.contains("..") else {
      throw AppStoreConnectError.invalidConnection("Apple returned an invalid resource identifier.")
    }
    return normalized
  }

  private func getAll<Resource: Decodable>(_ initialURL: URL) async throws -> [Resource] {
    var nextURL: URL? = initialURL
    var resources: [Resource] = []
    var pageCount = 0
    while let pageURL = nextURL {
      guard pageURL.scheme == "https", pageURL.host == baseURL.host else {
        throw AppStoreConnectError.unsafeRedirect(pageURL.host ?? "unknown")
      }
      let document: PagedDocument<Resource> = try await get(pageURL)
      resources.append(contentsOf: document.data)
      nextURL = document.links?.next
      pageCount += 1
      guard pageCount < 100 || nextURL == nil else {
        throw AppStoreConnectError.invalidConnection(
          "App Store Connect returned more data pages than Lys can safely load in one refresh.")
      }
    }
    return resources
  }

  private func get<Response: Decodable>(_ url: URL) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(try signer.token())", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw AppStoreConnectError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let error = try? JSONDecoder().decode(APIErrorDocument.self, from: data)
      let message =
        error?.errors.map(\.displayMessage).joined(separator: " · ")
        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw AppStoreConnectError.api(status: http.statusCode, message: message)
    }
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw AppStoreConnectError.invalidResponse
    }
  }

  private func send<Response: Decodable, Body: Encodable>(
    _ url: URL, method: String, body: Body
  ) async throws -> Response {
    let data = try await sendData(url, method: method, body: body)
    do { return try JSONDecoder().decode(Response.self, from: data) }
    catch { throw AppStoreConnectError.invalidResponse }
  }

  private func sendWithoutResponse<Body: Encodable>(
    _ url: URL, method: String, body: Body?
  ) async throws {
    _ = try await sendData(url, method: method, body: body)
  }

  private func sendData<Body: Encodable>(
    _ url: URL, method: String, body: Body?
  ) async throws -> Data {
    guard url.scheme == "https", url.host == baseURL.host else {
      throw AppStoreConnectError.unsafeRedirect(url.host ?? "unknown")
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(try signer.token())", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpBody = try JSONEncoder().encode(body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
    return data
  }

  private func performUpload(_ operation: UploadOperation, source: Data) async throws {
    guard let url = URL(string: operation.url), url.scheme == "https",
      operation.offset >= 0, operation.length > 0,
      operation.offset + operation.length <= source.count
    else { throw AppStoreConnectError.invalidResponse }
    var request = URLRequest(url: url)
    request.httpMethod = operation.method
    for header in operation.requestHeaders ?? [] {
      request.setValue(header.value, forHTTPHeaderField: header.name)
    }
    request.httpBody = source.subdata(in: operation.offset..<(operation.offset + operation.length))
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
  }

  private func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { throw AppStoreConnectError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let error = try? JSONDecoder().decode(APIErrorDocument.self, from: data)
      let message = error?.errors.map(\.displayMessage).joined(separator: " · ")
        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw AppStoreConnectError.api(status: http.statusCode, message: message)
    }
  }
}

private struct ResourceIdentifier: Codable {
  var type: String
  var id: String
}
private struct RelationshipLinkagesRequest: Encodable { var data: [ResourceIdentifier] }

private struct BetaTesterCreateRequest: Encodable {
  struct DataValue: Encodable {
    struct Attributes: Encodable {
      var firstName: String?
      var lastName: String?
      var email: String
    }
    struct Relationships: Encodable {
      struct BetaGroups: Encodable { var data: [ResourceIdentifier] }
      var betaGroups: BetaGroups
    }
    var type: String
    var attributes: Attributes
    var relationships: Relationships
  }
  var data: DataValue
}

private struct ScreenshotCreateRequest: Encodable {
  struct DataValue: Encodable {
    struct Attributes: Encodable {
      var fileSize: Int
      var fileName: String
    }
    struct Relationships: Encodable {
      struct ScreenshotSet: Encodable { var data: ResourceIdentifier }
      var appScreenshotSet: ScreenshotSet
    }
    var type: String
    var attributes: Attributes
    var relationships: Relationships
  }
  var data: DataValue
}

private struct ScreenshotUpdateRequest: Encodable {
  struct DataValue: Encodable {
    struct Attributes: Encodable {
      var sourceFileChecksum: String
      var uploaded: Bool
    }
    var type: String
    var id: String
    var attributes: Attributes
  }
  var data: DataValue
}

private struct UploadOperation: Decodable {
  struct Header: Decodable {
    var name: String
    var value: String
  }
  var method: String
  var url: String
  var length: Int
  var offset: Int
  var requestHeaders: [Header]?
}

private struct PagedDocument<Resource: Decodable>: Decodable {
  struct Links: Decodable { var next: URL? }
  var data: [Resource]
  var links: Links?
}

private struct BetaTesterDocument: Decodable { var data: BetaTesterResource }
private struct ScreenshotDocument: Decodable { var data: ScreenshotResource }

private struct ResourceLinkage: Decodable {
  var id: String
}

private struct ToOneRelationship: Decodable {
  var data: ResourceLinkage?
}

private struct RelationshipCount: Decodable {
  struct Meta: Decodable {
    struct Paging: Decodable { var total: Int? }
    var paging: Paging?
  }
  var meta: Meta?
}

private struct AppStoreVersionResource: Decodable {
  struct Attributes: Decodable {
    var platform: String?
    var versionString: String?
    var appVersionState: String?
    var releaseType: String?
    var earliestReleaseDate: String?
    var downloadable: Bool?
    var createdDate: String?
  }
  struct Relationships: Decodable { var build: ToOneRelationship? }
  var id: String
  var attributes: Attributes?
  var relationships: Relationships?

  var version: AppStoreVersion {
    .init(
      id: id, platform: attributes?.platform ?? "UNKNOWN",
      versionString: attributes?.versionString ?? "Unknown",
      state: attributes?.appVersionState ?? "UNKNOWN",
      releaseType: attributes?.releaseType,
      earliestReleaseDate: AppStoreDateParser.date(attributes?.earliestReleaseDate),
      createdDate: AppStoreDateParser.date(attributes?.createdDate),
      downloadable: attributes?.downloadable, buildID: relationships?.build?.data?.id)
  }
}

private struct BuildResource: Decodable {
  struct Attributes: Decodable {
    var version: String?
    var uploadedDate: String?
    var expirationDate: String?
    var expired: Bool?
    var minOsVersion: String?
    var processingState: String?
    var buildAudienceType: String?
    var usesNonExemptEncryption: Bool?
  }
  struct Relationships: Decodable { var preReleaseVersion: ToOneRelationship? }
  var id: String
  var attributes: Attributes?
  var relationships: Relationships?

  func build(marketingVersions: [String: String?]) -> AppStoreBuild {
    let prereleaseID = relationships?.preReleaseVersion?.data?.id
    return .init(
      id: id, version: attributes?.version ?? "Unknown",
      marketingVersion: prereleaseID.flatMap { marketingVersions[$0] ?? nil },
      uploadedDate: AppStoreDateParser.date(attributes?.uploadedDate),
      expirationDate: AppStoreDateParser.date(attributes?.expirationDate),
      expired: attributes?.expired ?? false, minimumOSVersion: attributes?.minOsVersion,
      processingState: attributes?.processingState ?? "UNKNOWN",
      audienceType: attributes?.buildAudienceType,
      usesNonExemptEncryption: attributes?.usesNonExemptEncryption)
  }
}

private struct PreReleaseVersionResource: Decodable {
  struct Attributes: Decodable { var version: String? }
  var id: String
  var attributes: Attributes?
}

private struct BetaGroupResource: Decodable {
  struct Attributes: Decodable {
    var name: String?
    var isInternalGroup: Bool?
    var hasAccessToAllBuilds: Bool?
    var publicLinkEnabled: Bool?
    var feedbackEnabled: Bool?
  }
  struct Relationships: Decodable { var betaTesters: RelationshipCount? }
  var id: String
  var attributes: Attributes?
  var relationships: Relationships?

  var group: AppStoreBetaGroup {
    .init(
      id: id, name: attributes?.name ?? "Unnamed group",
      isInternal: attributes?.isInternalGroup ?? false,
      hasAccessToAllBuilds: attributes?.hasAccessToAllBuilds ?? false,
      publicLinkEnabled: attributes?.publicLinkEnabled ?? false,
      feedbackEnabled: attributes?.feedbackEnabled ?? false,
      testerCount: relationships?.betaTesters?.meta?.paging?.total)
  }
}

private struct BetaTesterResource: Decodable {
  struct Attributes: Decodable {
    var firstName: String?
    var lastName: String?
    var email: String?
    var inviteType: String?
    var state: String?
  }
  var id: String
  var attributes: Attributes?

  var tester: AppStoreBetaTester {
    .init(
      id: id, firstName: attributes?.firstName, lastName: attributes?.lastName,
      email: attributes?.email ?? "Unknown email", inviteType: attributes?.inviteType,
      state: attributes?.state)
  }
}

private struct VersionLocalizationResource: Decodable {
  struct Attributes: Decodable {
    var locale: String?
    var whatsNew: String?
    var promotionalText: String?
  }
  var id: String
  var attributes: Attributes?

  var localization: AppStoreVersionLocalization {
    .init(
      id: id, locale: attributes?.locale ?? "und", whatsNew: attributes?.whatsNew,
      promotionalText: attributes?.promotionalText)
  }
}

private struct ScreenshotSetResource: Decodable {
  struct Attributes: Decodable { var screenshotDisplayType: String? }
  var id: String
  var attributes: Attributes?
}

private struct ScreenshotResource: Decodable {
  struct Attributes: Decodable {
    struct ImageAsset: Decodable {
      var templateUrl: String?
      var width: Int?
      var height: Int?
    }
    struct DeliveryState: Decodable { var state: String? }
    var fileSize: Int?
    var fileName: String?
    var imageAsset: ImageAsset?
    var assetDeliveryState: DeliveryState?
    var uploadOperations: [UploadOperation]?
  }
  var id: String
  var attributes: Attributes?

  var screenshot: AppStoreScreenshot {
    .init(
      id: id, fileName: attributes?.fileName ?? "Screenshot", fileSize: attributes?.fileSize,
      width: attributes?.imageAsset?.width, height: attributes?.imageAsset?.height,
      templateURL: attributes?.imageAsset?.templateUrl,
      deliveryState: attributes?.assetDeliveryState?.state)
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct ScreenshotFeedbackResource: Decodable {
  struct Attributes: Decodable {
    struct ScreenshotImage: Decodable { var url: String? }
    var createdDate: String?
    var comment: String?
    var deviceModel: String?
    var osVersion: String?
    var buildBundleId: String?
    var screenshots: [ScreenshotImage]?
  }
  struct Relationships: Decodable { var build: ToOneRelationship? }
  var id: String
  var attributes: Attributes?
  var relationships: Relationships?

  var feedback: AppStoreFeedback {
    .init(
      id: id, kind: .screenshot,
      createdDate: AppStoreDateParser.date(attributes?.createdDate),
      comment: attributes?.comment, deviceModel: attributes?.deviceModel,
      osVersion: attributes?.osVersion, buildBundleID: attributes?.buildBundleId,
      imageURL: attributes?.screenshots?.first?.url.flatMap(URL.init(string:)),
      buildID: relationships?.build?.data?.id)
  }
}

private struct CrashFeedbackResource: Decodable {
  struct Attributes: Decodable {
    var createdDate: String?
    var comment: String?
    var deviceModel: String?
    var osVersion: String?
    var buildBundleId: String?
  }
  struct Relationships: Decodable { var build: ToOneRelationship? }
  var id: String
  var attributes: Attributes?
  var relationships: Relationships?

  var feedback: AppStoreFeedback {
    .init(
      id: id, kind: .crash, createdDate: AppStoreDateParser.date(attributes?.createdDate),
      comment: attributes?.comment, deviceModel: attributes?.deviceModel,
      osVersion: attributes?.osVersion, buildBundleID: attributes?.buildBundleId,
      buildID: relationships?.build?.data?.id)
  }
}

private enum AppStoreDateParser {
  static func date(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}

private struct AppsDocument: Decodable {
  struct Links: Decodable { var next: URL? }
  var data: [Resource]
  var links: Links?

  struct Resource: Decodable {
    struct Attributes: Decodable {
      var name: String
      var bundleId: String
      var sku: String
      var primaryLocale: String
    }
    var id: String
    var attributes: Attributes

    var app: AppStoreApp {
      .init(
        id: id, name: attributes.name, bundleID: attributes.bundleId, sku: attributes.sku,
        primaryLocale: attributes.primaryLocale)
    }
  }
}

private struct APIErrorDocument: Decodable {
  struct APIError: Decodable {
    var title: String?
    var detail: String?
    var code: String?
    var displayMessage: String {
      detail ?? title ?? code ?? "Apple did not provide an error description."
    }
  }
  var errors: [APIError]
}
