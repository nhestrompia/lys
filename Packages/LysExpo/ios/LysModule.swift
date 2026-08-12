import ExpoModulesCore

public final class LysModule: Module {
  public func definition() -> ModuleDefinition {
    Name("Lys")

    Function("isTestSession") {
      ProcessInfo.processInfo.arguments.contains("-LysTesting")
    }

    Function("credential") { (environmentKey: String) -> String? in
      guard ProcessInfo.processInfo.arguments.contains("-LysTesting") else { return nil }
      return ProcessInfo.processInfo.environment[environmentKey]
    }
  }
}
