import ExpoModulesCore

public final class LysModule: Module {
  public func definition() -> ModuleDefinition {
    Name("Lys")

    Function("isTestSession") {
      ProcessInfo.processInfo.arguments.contains("-LysTesting")
    }

    Function("contextID") {
      guard ProcessInfo.processInfo.arguments.contains("-LysTesting") else { return nil as String? }
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "-LysContext"), arguments.indices.contains(index + 1)
      else { return nil as String? }
      let value = arguments[index + 1]
      return value.isEmpty ? nil : value
    }

    Function("resetRequested") {
      ProcessInfo.processInfo.arguments.contains("-LysTesting")
        && ProcessInfo.processInfo.arguments.contains("-LysReset")
    }

    Function("credential") { (environmentKey: String) -> String? in
      guard ProcessInfo.processInfo.arguments.contains("-LysTesting") else { return nil }
      return ProcessInfo.processInfo.environment[environmentKey]
    }
  }
}
