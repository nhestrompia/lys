import Foundation

public enum ExpoCompatibilityError: Error, LocalizedError {
  case unexpectedGeneratedSource(String)

  public var errorDescription: String? {
    switch self {
    case .unexpectedGeneratedSource(let path):
      "The generated dependency source at \(path) does not match the supported compatibility repair. Regenerate the Expo iOS project and try again."
    }
  }
}

public enum ExpoCompatibility {
  private static let fmtMarker = "// iosdev: Apple Clang 21 fmt consteval compatibility"
  private static let fmtAnchor =
    "#elif defined(__apple_build_version__) && __apple_build_version__ < 14000029L"
  private static let fmtReplacement = """
    #elif defined(__apple_build_version__) && __apple_build_version__ >= 21000000L
    #  define FMT_USE_CONSTEVAL 0  \(fmtMarker)
    \(fmtAnchor)
    """
  private static let mmkvMarker = "// iosdev: Apple Clang 21 MMKV secure-wipe compatibility"
  private static let mmkvAnchor = """
    #elif defined(__STDC_LIB_EXT1__) || defined(MMKV_APPLE)
        // C11 Annex K, if the implementation actually provides it.
        (void)memset_s(ptr, len, 0, len);
    """
  private static let mmkvReplacement = """
    #elif defined(__STDC_LIB_EXT1__)
        // C11 Annex K, if the implementation actually provides it.
        (void)memset_s(ptr, len, 0, len);
    #elif defined(MMKV_APPLE)
        \(mmkvMarker)
        volatile unsigned char* p = static_cast<volatile unsigned char*>(ptr);
        while (len--) {
            *p++ = 0;
        }
    """

  public static func fmtHeader(for container: URL) -> URL {
    container.deletingLastPathComponent().appending(path: "Pods/fmt/include/fmt/base.h")
  }

  public static func mmkvAESSource(for container: URL) -> URL {
    container.deletingLastPathComponent().appending(
      path: "Pods/MMKVCore/Core/aes/AESCrypt.cpp")
  }

  public static func needsFMTConstevalRepair(at header: URL) -> Bool {
    guard let content = try? String(contentsOf: header, encoding: .utf8) else { return false }
    return !content.contains(fmtMarker) && content.contains(fmtAnchor)
  }

  @discardableResult
  public static func applyFMTConstevalRepair(at header: URL) throws -> Bool {
    let content = try String(contentsOf: header, encoding: .utf8)
    if content.contains(fmtMarker) { return false }
    guard content.contains(fmtAnchor) else {
      throw ExpoCompatibilityError.unexpectedGeneratedSource(header.path)
    }
    let patched = content.replacingOccurrences(of: fmtAnchor, with: fmtReplacement)
    try patched.write(to: header, atomically: true, encoding: .utf8)
    return true
  }

  public static func needsMMKVSecureWipeRepair(at source: URL) -> Bool {
    guard let content = try? String(contentsOf: source, encoding: .utf8) else { return false }
    return !content.contains(mmkvMarker) && content.contains(mmkvAnchor)
  }

  @discardableResult
  public static func applyMMKVSecureWipeRepair(at source: URL) throws -> Bool {
    let content = try String(contentsOf: source, encoding: .utf8)
    if content.contains(mmkvMarker) { return false }
    guard content.contains(mmkvAnchor) else {
      throw ExpoCompatibilityError.unexpectedGeneratedSource(source.path)
    }
    let patched = content.replacingOccurrences(of: mmkvAnchor, with: mmkvReplacement)
    try patched.write(to: source, atomically: true, encoding: .utf8)
    return true
  }
}
