import Foundation
@preconcurrency import Security

/// Reads flow credentials without returning them through the agent tool surface. Repository
/// blueprints contain only logical secret IDs; the local `.iosdev/config.json` maps those IDs to
/// Keychain accounts.
public enum BlueprintSecretStore {
  public static let service = "com.operate.iosdev.flow-secrets"

  public static func read(account: String, service: String = service) -> String? {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ] as CFDictionary,
      &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
