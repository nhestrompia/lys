import Foundation

public struct CommandSpec: Codable, Equatable, Sendable {
  public var executable: URL
  public var arguments: [String]
  public var environment: [String: String]
  public init(executable: URL, arguments: [String], environment: [String: String] = [:]) {
    precondition(executable.path.hasPrefix("/"))
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
  }
}

public enum SimulatorAppearance: String, Codable, Sendable { case light, dark }

public enum AppleCommandBuilder {
  public static func boot(simctl: URL, udid: String) -> CommandSpec {
    .init(executable: simctl, arguments: ["boot", udid])
  }
  public static func shutdown(simctl: URL, udid: String) -> CommandSpec {
    .init(executable: simctl, arguments: ["shutdown", udid])
  }
  public static func install(simctl: URL, udid: String, app: URL) -> CommandSpec {
    .init(executable: simctl, arguments: ["install", udid, app.path])
  }
  public static func launch(simctl: URL, udid: String, bundleID: String, arguments: [String] = [])
    -> CommandSpec
  { .init(executable: simctl, arguments: ["launch", udid, bundleID] + arguments) }
  public static func terminate(simctl: URL, udid: String, bundleID: String) -> CommandSpec {
    .init(executable: simctl, arguments: ["terminate", udid, bundleID])
  }
  public static func resetAppData(simctl: URL, udid: String, bundleID: String) -> CommandSpec {
    .init(executable: simctl, arguments: ["uninstall", udid, bundleID])
  }
  public static func appearance(simctl: URL, udid: String, value: SimulatorAppearance)
    -> CommandSpec
  { .init(executable: simctl, arguments: ["ui", udid, "appearance", value.rawValue]) }
  public static func orientation(simctl: URL, udid: String, value: String) -> CommandSpec {
    .init(executable: simctl, arguments: ["io", udid, "rotate", value])
  }
  public static func statusBar(simctl: URL, udid: String, overrides: [String: String])
    -> CommandSpec
  {
    .init(
      executable: simctl,
      arguments: ["status_bar", udid, "override"]
        + overrides.sorted { $0.key < $1.key }.flatMap { ["--\($0.key)", $0.value] })
  }
  public static func screenshot(simctl: URL, udid: String, output: URL) -> CommandSpec {
    .init(executable: simctl, arguments: ["io", udid, "screenshot", output.path])
  }
  public static func logStream(simctl: URL, udid: String, process: String) -> CommandSpec {
    .init(
      executable: simctl,
      arguments: [
        "spawn", udid, "log", "stream", "--style", "json", "--predicate", "process == '\(process)'",
      ])
  }
  public static func logQuery(simctl: URL, udid: String, process: String, seconds: Int)
    -> CommandSpec
  {
    .init(
      executable: simctl,
      arguments: [
        "spawn", udid, "log", "show", "--style", "compact", "--last", "\(seconds)s",
        "--predicate", "process == \"\(process)\"",
      ])
  }
}
