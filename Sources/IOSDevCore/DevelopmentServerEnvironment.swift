import Foundation

public enum DevelopmentServerEnvironment {
  /// Environment overrides for a local, long-running Metro server.
  ///
  /// Do not set `CI` here. Metro disables file watching when it detects a CI environment, which
  /// prevents Expo Fast Refresh from observing source changes after the initial bundle is served.
  public static func local(searchPath: String) -> [String: String] {
    [
      "PATH": searchPath,
      "BROWSER": "none",
    ]
  }
}
