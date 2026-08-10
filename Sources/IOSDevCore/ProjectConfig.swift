import Foundation

public struct IOSDevConfiguration: Codable, Sendable {
  public struct SecretReference: Codable, Sendable {
    public var environmentKey: String
    public var keychainAccount: String
  }
  public struct DeviceProfile: Codable, Sendable {
    public var deviceTypeContains: String
    public var runtimeContains: String?
  }
  public struct SetupCommand: Codable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var enabled: Bool?
  }
  public var schemaVersion: Int
  public var project: String?
  public var workspace: String?
  public var scheme: String?
  public var target: String?
  public var buildConfiguration: String?
  public var launchArguments: [String]?
  public var environment: [String: String]?
  public var secrets: [SecretReference]?
  public var setupCommands: [SetupCommand]?
  public var deviceProfiles: [String: DeviceProfile]?
  public var resetAppData: Bool?
  public var startupTimeoutSeconds: Double?

  public static func load(from url: URL) throws -> Self {
    let data = try Data(contentsOf: url)
    let probe = try JSONDecoder().decode([String: JSONValue].self, from: data)
    guard probe["schemaVersion"] == .number(1) else {
      throw RPCError(code: -32040, message: "Unsupported .iosdev configuration schema version")
    }
    return try JSONDecoder().decode(Self.self, from: data)
  }
}
