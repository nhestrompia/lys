import CryptoKit
import Foundation
import Testing

@testable import IOSDevCore

@Test func appStoreTeamTokenHasBoundedClaimsAndValidES256Signature() throws {
  let key = P256.Signing.PrivateKey()
  let connection = AppStoreConnection(
    label: "Release", keyID: "ABC123XYZ", issuerID: "issuer-id", keyKind: .team)
  let signer = try AppStoreConnectTokenSigner(
    connection: connection, privateKeyPEM: Data(key.pemRepresentation.utf8))
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let token = try signer.token(now: now, lifetime: 900)
  let segments = token.split(separator: ".").map(String.init)
  #expect(segments.count == 3)

  let header = try jsonObject(segments[0])
  let payload = try jsonObject(segments[1])
  #expect(header["alg"] as? String == "ES256")
  #expect(header["kid"] as? String == "ABC123XYZ")
  #expect(payload["iss"] as? String == "issuer-id")
  #expect(payload["aud"] as? String == "appstoreconnect-v1")
  #expect(payload["iat"] as? Int == 1_800_000_000)
  #expect(payload["exp"] as? Int == 1_800_000_900)
  #expect(payload["sub"] == nil)

  let signatureData = try #require(base64URLData(segments[2]))
  #expect(signatureData.count == 64)
  let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
  #expect(
    key.publicKey.isValidSignature(
      signature, for: Data("\(segments[0]).\(segments[1])".utf8)))
}

@Test func appStoreIndividualTokenUsesSubjectInsteadOfIssuer() throws {
  let key = P256.Signing.PrivateKey()
  let connection = AppStoreConnection(
    label: "Personal", keyID: "KEY", issuerID: nil, keyKind: .individual)
  let signer = try AppStoreConnectTokenSigner(
    connection: connection, privateKeyPEM: Data(key.pemRepresentation.utf8))
  let token = try signer.token(now: Date(timeIntervalSince1970: 1_800_000_000))
  let payload = try jsonObject(String(token.split(separator: ".")[1]))
  #expect(payload["sub"] as? String == "user")
  #expect(payload["iss"] == nil)
}

@Test func appStoreTokenRejectsLifetimeOverTwentyMinutes() throws {
  let key = P256.Signing.PrivateKey()
  let connection = AppStoreConnection(
    label: "Release", keyID: "KEY", issuerID: "issuer", keyKind: .team)
  let signer = try AppStoreConnectTokenSigner(
    connection: connection, privateKeyPEM: Data(key.pemRepresentation.utf8))
  #expect(throws: AppStoreConnectError.self) {
    try signer.token(lifetime: 1_201)
  }
}

@Test func sqliteStorePersistsOnlyAppStoreConnectionMetadata() async throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let store = try SQLiteStore(url: root.appending(path: "metadata.sqlite3"))
  let connection = AppStoreConnection(
    label: "Release", keyID: "KEY", issuerID: "issuer", keyKind: .team)
  try await store.saveAppStoreConnection(connection)
  let loaded = try await store.appStoreConnections()
  #expect(loaded == [connection])
  try await store.deleteAppStoreConnection(id: connection.id)
  #expect(try await store.appStoreConnections().isEmpty)
}

@Test func appStoreCredentialSessionReadsKeychainOncePerAccount() async throws {
  let connectionID = UUID()
  let key = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
  let loader = CredentialLoaderCounter(key: key)
  let session = AppStoreCredentialSession { requestedID in
    #expect(requestedID == connectionID)
    return loader.load()
  }

  #expect(try await session.privateKey(for: connectionID) == key)
  #expect(try await session.privateKey(for: connectionID) == key)
  #expect(loader.count == 1)

  await session.remove(connectionID: connectionID)
  #expect(try await session.privateKey(for: connectionID) == key)
  #expect(loader.count == 2)
}

@Test func appStoreClientLoadsLiveDeploymentSections() async throws {
  let key = P256.Signing.PrivateKey()
  let connection = AppStoreConnection(
    label: "Release", keyID: "KEY", issuerID: "issuer", keyKind: .team)
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [AppStoreFixtureURLProtocol.self]
  AppStoreFixtureURLProtocol.response = { request in
    if request.url?.host == "api.appstoreconnect.apple.com" {
      #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
    } else {
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
    let path = try #require(request.url?.path)
    switch path {
    case "/v1/apps/app-1/appStoreVersions":
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"appStoreVersions","id":"version-1","attributes":{"platform":"IOS","versionString":"2.4","appVersionState":"READY_FOR_DISTRIBUTION","releaseType":"MANUAL","createdDate":"2026-08-10T12:30:00.000Z"},"relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/app-1/appStoreVersions"}}
        """)
    case "/v1/apps/app-1/builds":
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"builds","id":"build-1","attributes":{"version":"42","uploadedDate":"2026-08-10T12:00:00Z","expired":false,"minOsVersion":"17.0","processingState":"VALID","buildAudienceType":"APP_STORE_ELIGIBLE"},"relationships":{"preReleaseVersion":{"data":{"type":"preReleaseVersions","id":"pre-1"}}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/app-1/builds"}}
        """)
    case "/v1/apps/app-1/preReleaseVersions":
      let queryNames = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.map(\.name) ?? []
      #expect(!queryNames.contains("filter[platform]"))
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"preReleaseVersions","id":"pre-1","attributes":{"version":"2.4","platform":"IOS"}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/app-1/preReleaseVersions"}}
        """)
    case "/v1/betaGroups":
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"betaGroups","id":"group-1","attributes":{"name":"Internal QA","isInternalGroup":true,"hasAccessToAllBuilds":true,"publicLinkEnabled":false,"feedbackEnabled":true},"relationships":{"betaTesters":{"meta":{"paging":{"total":7,"limit":1}},"data":[]}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/betaGroups"}}
        """)
    case "/v1/betaGroups/group-1/betaTesters":
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"betaTesters","id":"tester-1","attributes":{"firstName":"Ada","lastName":"Lovelace","email":"ada@example.com","inviteType":"EMAIL","state":"ACCEPTED"}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/betaGroups/group-1/betaTesters"}}
        """)
    case "/v1/apps/app-1/betaFeedbackScreenshotSubmissions":
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"betaFeedbackScreenshotSubmissions","id":"feedback-1","attributes":{"createdDate":"2026-08-11T09:15:00Z","comment":"Spacing is clipped","deviceModel":"iPhone 17 Pro","osVersion":"26.0","buildBundleId":"com.example.app","screenshots":[{"url":"https://example.invalid/feedback.png","width":1200,"height":2600}]},"relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/app-1/betaFeedbackScreenshotSubmissions"}}
        """)
    case "/v1/apps/app-1/betaFeedbackCrashSubmissions":
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"betaFeedbackCrashSubmissions","id":"crash-1","attributes":{"createdDate":"2026-08-11T08:00:00Z","deviceModel":"iPhone 17 Pro","osVersion":"26.0","buildBundleId":"com.example.app"},"relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/app-1/betaFeedbackCrashSubmissions"}}
        """)
    case "/v1/appStoreVersions/version-1/appStoreVersionLocalizations":
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"appStoreVersionLocalizations","id":"localization-1","attributes":{"locale":"en-US","whatsNew":"Faster launch.","promotionalText":"Built for teams."}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/appStoreVersions/version-1/appStoreVersionLocalizations"}}
        """)
    case "/v1/appStoreVersionLocalizations/localization-1/appScreenshotSets":
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"appScreenshotSets","id":"set-1","attributes":{"screenshotDisplayType":"APP_IPHONE_67"}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/localization-1/appScreenshotSets"}}
        """)
    case "/v1/appScreenshotSets/set-1/appScreenshots":
      return fixtureResponse(
        request,
        """
        {"data":[{"type":"appScreenshots","id":"screenshot-1","attributes":{"fileSize":123456,"fileName":"home.png","imageAsset":{"templateUrl":"https://example.invalid/{w}x{h}.{f}","width":1290,"height":2796},"assetDeliveryState":{"state":"COMPLETE"}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/appScreenshotSets/set-1/appScreenshots"}}
        """)
    case "/v1/betaTesters":
      #expect(request.httpMethod == "POST")
      #expect(String(data: requestBodyData(request), encoding: .utf8)?.contains("ada+new@example.com") == true)
      return fixtureResponse(
        request,
        """
        {"data":{"type":"betaTesters","id":"tester-new","attributes":{"firstName":"Ada","lastName":"Byron","email":"ada+new@example.com","state":"INVITED"}},"links":{"self":"https://api.appstoreconnect.apple.com/v1/betaTesters/tester-new"}}
        """, status: 201)
    case "/v1/betaGroups/group-1/relationships/betaTesters":
      #expect(request.httpMethod == "DELETE")
      return fixtureResponse(request, "", status: 204)
    case "/v1/appScreenshots":
      #expect(request.httpMethod == "POST")
      return fixtureResponse(
        request,
        """
        {"data":{"type":"appScreenshots","id":"screenshot-new","attributes":{"fileSize":3,"fileName":"new.png","uploadOperations":[{"method":"PUT","url":"https://upload.example.invalid/asset","length":3,"offset":0,"requestHeaders":[{"name":"Content-Type","value":"application/octet-stream"}]}]}},"links":{"self":"https://api.appstoreconnect.apple.com/v1/appScreenshots/screenshot-new"}}
        """, status: 201)
    case "/asset":
      #expect(request.httpMethod == "PUT")
      #expect(requestBodyData(request) == Data("abc".utf8))
      return fixtureResponse(request, "")
    case "/v1/appScreenshots/screenshot-new":
      if request.httpMethod == "PATCH" {
        let body = String(data: requestBodyData(request), encoding: .utf8) ?? ""
        #expect(body.contains("900150983cd24fb0d6963f7d28e17f72"))
        return fixtureResponse(
          request,
          """
          {"data":{"type":"appScreenshots","id":"screenshot-new","attributes":{"fileSize":3,"fileName":"new.png","assetDeliveryState":{"state":"UPLOAD_COMPLETE"}}},"links":{"self":"https://api.appstoreconnect.apple.com/v1/appScreenshots/screenshot-new"}}
          """)
      }
      #expect(request.httpMethod == "DELETE")
      return fixtureResponse(request, "", status: 204)
    default:
      Issue.record("Unexpected App Store fixture request: \(path)")
      return fixtureResponse(request, "{\"data\":[]}", status: 404)
    }
  }
  defer { AppStoreFixtureURLProtocol.response = nil }

  let client = try AppStoreConnectClient(
    connection: connection, privateKeyPEM: Data(key.pemRepresentation.utf8),
    session: URLSession(configuration: configuration))
  let versions = try await client.listAppStoreVersions(appID: "app-1")
  let builds = try await client.listBuilds(appID: "app-1")
  let groups = try await client.listBetaGroups(appID: "app-1")
  let screenshotFeedback = try await client.listScreenshotFeedback(appID: "app-1")
  let crashFeedback = try await client.listCrashFeedback(appID: "app-1")
  let localizations = try await client.listVersionLocalizations(versionID: "version-1")
  let screenshots = try await client.listScreenshotSets(
    versionID: "version-1", preferredLocale: "en-US")
  let addedTester = try await client.addBetaTester(
    email: "ada+new@example.com", firstName: "Ada", lastName: "Byron", groupID: "group-1")
  try await client.removeBetaTester("tester-new", fromGroup: "group-1")
  let uploadedScreenshot = try await client.uploadScreenshot(
    data: Data("abc".utf8), fileName: "new.png", screenshotSetID: "set-1")
  try await client.deleteScreenshot(id: uploadedScreenshot.id)

  #expect(versions.first?.versionString == "2.4")
  #expect(versions.first?.buildID == "build-1")
  #expect(builds.first?.version == "42")
  #expect(builds.first?.marketingVersion == "2.4")
  #expect(groups.first?.testerCount == 1)
  #expect(groups.first?.testers.first?.email == "ada@example.com")
  #expect(screenshotFeedback.first?.comment == "Spacing is clipped")
  #expect(crashFeedback.first?.kind == .crash)
  #expect(localizations.first?.whatsNew == "Faster launch.")
  #expect(screenshots.first?.screenshots.first?.fileName == "home.png")
  #expect(screenshots.first?.screenshots.first?.downloadURL?.absoluteString == "https://example.invalid/1290x2796.png")
  #expect(addedTester.email == "ada+new@example.com")
  #expect(uploadedScreenshot.deliveryState == "UPLOAD_COMPLETE")
}

private func jsonObject(_ encoded: String) throws -> [String: Any] {
  let data = try #require(base64URLData(encoded))
  return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func base64URLData(_ encoded: String) -> Data? {
  var base64 = encoded.replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  let remainder = base64.count % 4
  if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
  return Data(base64Encoded: base64)
}

private func fixtureResponse(
  _ request: URLRequest, _ body: String, status: Int = 200
) -> (HTTPURLResponse, Data) {
  let response = HTTPURLResponse(
    url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
    headerFields: ["Content-Type": "application/json"])!
  return (response, Data(body.utf8))
}

private func requestBodyData(_ request: URLRequest) -> Data {
  if let body = request.httpBody { return body }
  guard let stream = request.httpBodyStream else { return Data() }
  stream.open()
  defer { stream.close() }
  var result = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while stream.hasBytesAvailable {
    let count = stream.read(&buffer, maxLength: buffer.count)
    guard count > 0 else { break }
    result.append(buffer, count: count)
  }
  return result
}

private final class AppStoreFixtureURLProtocol: URLProtocol {
  nonisolated(unsafe) static var response: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      guard let response = Self.response else {
        throw URLError(.resourceUnavailable)
      }
      let (http, data) = try response(request)
      client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private final class CredentialLoaderCounter: @unchecked Sendable {
  private let lock = NSLock()
  private let key: Data
  private var reads = 0

  init(key: Data) {
    self.key = key
  }

  var count: Int {
    lock.withLock { reads }
  }

  func load() -> Data? {
    lock.withLock {
      reads += 1
      return key
    }
  }
}
