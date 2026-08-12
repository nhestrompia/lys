import Foundation
@preconcurrency import Security

/// Reads flow credentials without returning them through the agent tool surface. Repository
/// contracts contain only logical secret IDs; the local `.lys/config.json` may map those IDs to
/// Keychain accounts.
public enum BlueprintSecretStore {
  public static let service = "dev.lys.test-secrets"

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

  public static func write(_ value: String, account: String, service: String = service) throws {
    let lookup = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ] as CFDictionary
    let attributes = [kSecValueData as String: Data(value.utf8)] as CFDictionary
    let updated = SecItemUpdate(lookup, attributes)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else {
      throw RPCError(code: -32126, message: "Keychain update failed (\(updated))")
    }
    let inserted = SecItemAdd(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: Data(value.utf8),
      ] as CFDictionary,
      nil)
    guard inserted == errSecSuccess else {
      throw RPCError(code: -32126, message: "Keychain insert failed (\(inserted))")
    }
  }

  public static func delete(account: String, service: String = service) throws {
    let status = SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ] as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw RPCError(code: -32126, message: "Keychain delete failed (\(status))")
    }
  }

  public static func accounts(service: String = service) -> [String] {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecReturnAttributes as String: true,
        kSecMatchLimit as String: kSecMatchLimitAll,
      ] as CFDictionary,
      &item)
    guard status == errSecSuccess, let rows = item as? [[String: Any]] else { return [] }
    return rows.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
  }
}
