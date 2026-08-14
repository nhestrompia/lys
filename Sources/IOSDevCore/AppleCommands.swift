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

public struct AxeKeyboardModifiers: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let shift = Self(rawValue: 1 << 0)
  public static let control = Self(rawValue: 1 << 1)
  public static let option = Self(rawValue: 1 << 2)
  public static let command = Self(rawValue: 1 << 3)
}

public enum AppleCommandBuilder {
  public static func boot(simctl: URL, udid: String) -> CommandSpec {
    .init(executable: simctl, arguments: ["boot", udid])
  }
  public static func bootStatus(simctl: URL, udid: String) -> CommandSpec {
    .init(executable: simctl, arguments: ["bootstatus", udid, "-b"])
  }
  public static func shutdown(simctl: URL, udid: String) -> CommandSpec {
    .init(executable: simctl, arguments: ["shutdown", udid])
  }
  public static func install(simctl: URL, udid: String, app: URL) -> CommandSpec {
    .init(executable: simctl, arguments: ["install", udid, app.path])
  }
  public static func launch(
    simctl: URL, udid: String, bundleID: String, arguments: [String] = [],
    terminateRunningProcess: Bool = false
  ) -> CommandSpec {
    .init(
      executable: simctl,
      arguments: ["launch"] + (terminateRunningProcess ? ["--terminate-running-process"] : [])
        + [udid, bundleID] + arguments)
  }
  /// Builds a Simulator launch whose protected values live only in the child environment. Values
  /// are never interpolated into command arguments, logs, or the agent-visible contract.
  public static func authenticatedLaunch(
    simctl: URL, udid: String, bundleID: String, developerDirectory: String,
    values: [String: String], arguments: [String] = ["-LysTesting"],
    terminateRunningProcess: Bool = false
  ) -> CommandSpec {
    var environment = ["DEVELOPER_DIR": developerDirectory]
    for (key, value) in values { environment["SIMCTL_CHILD_\(key)"] = value }
    return .init(
      executable: simctl,
      arguments: ["launch"] + (terminateRunningProcess ? ["--terminate-running-process"] : [])
        + [udid, bundleID] + arguments,
      environment: environment)
  }
  public static func configureMetro(
    simctl: URL, udid: String, bundleID: String, host: String = "127.0.0.1", port: Int = 8081
  ) -> [CommandSpec] {
    let domain = bundleID
    return [
      .init(
        executable: simctl,
        arguments: [
          "spawn", udid, "defaults", "write", domain, "RCT_jsLocation", "\(host):\(port)",
        ]),
      .init(
        executable: simctl,
        arguments: ["spawn", udid, "defaults", "write", domain, "RCT_enableDev", "-bool", "YES"]),
    ]
  }
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

  /// Converts a macOS key event into AXe HID input so the embedded Simulator never needs a
  /// separately opened Simulator.app window just to receive keyboard events.
  public static func axeKeyboard(
    axe: URL, udid: String, macKeyCode: Int, characters: String?,
    charactersIgnoringModifiers: String?, modifiers: AxeKeyboardModifiers
  ) -> CommandSpec? {
    let special: [Int: Int] = [
      36: 40, 48: 43, 49: 44, 51: 42, 53: 41, 117: 76,
      123: 80, 124: 79, 125: 81, 126: 82,
    ]
    let chordModifiers = axeModifierKeycodes(modifiers)
    if !chordModifiers.isEmpty,
      let key = charactersIgnoringModifiers?.lowercased().first.flatMap(axeKeycode)
        ?? special[macKeyCode]
    {
      return .init(
        executable: axe,
        arguments: [
          "key-combo", "--modifiers", chordModifiers.map(String.init).joined(separator: ","),
          "--key", String(key), "--udid", udid,
        ])
    }
    if let key = special[macKeyCode] {
      return .init(executable: axe, arguments: ["key", String(key), "--udid", udid])
    }
    guard let characters, !characters.isEmpty else { return nil }
    return .init(executable: axe, arguments: ["type", characters, "--udid", udid])
  }

  private static func axeModifierKeycodes(_ modifiers: AxeKeyboardModifiers) -> [Int] {
    var result: [Int] = []
    if modifiers.contains(.control) { result.append(224) }
    if modifiers.contains(.shift) { result.append(225) }
    if modifiers.contains(.option) { result.append(226) }
    if modifiers.contains(.command) { result.append(227) }
    return result
  }

  private static func axeKeycode(_ character: Character) -> Int? {
    if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 {
      let value = Int(scalar.value)
      if (97...122).contains(value) { return value - 97 + 4 }
      if (49...57).contains(value) { return value - 49 + 30 }
      if value == 48 { return 39 }
    }
    return nil
  }
}

/// Builds the process arguments owned by the Lys host. Contract-provided app arguments may not
/// override the testing, reset, or context markers that define the current isolation boundary.
enum LysHostLaunchArguments {
  static let reservedFlags = Set(["-LysTesting", "-LysReset", "-LysContext"])

  static func build(
    contextID: String?, resetRequested: Bool, additional: [String] = []
  ) -> [String] {
    var sanitized: [String] = []
    var index = additional.startIndex
    while index < additional.endIndex {
      let argument = additional[index]
      if argument == "-LysContext" {
        index = additional.index(after: index)
        if index < additional.endIndex { index = additional.index(after: index) }
        continue
      }
      if reservedFlags.contains(argument) {
        index = additional.index(after: index)
        continue
      }
      sanitized.append(argument)
      index = additional.index(after: index)
    }

    sanitized.append("-LysTesting")
    if resetRequested { sanitized.append("-LysReset") }
    if let contextID, !contextID.isEmpty {
      sanitized.append(contentsOf: ["-LysContext", contextID])
    }
    return sanitized
  }
}
