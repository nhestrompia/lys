import Foundation

public struct ProcessEvent: Codable, Sendable {
  public enum Stream: String, Codable, Sendable { case stdout, stderr, lifecycle }
  public var stream: Stream
  public var text: String
  public var timestamp: Date
  public init(stream: Stream, text: String, timestamp: Date = Date()) {
    self.stream = stream
    self.text = text
    self.timestamp = timestamp
  }
}

public struct ProcessOutcome: Codable, Sendable {
  public var terminationStatus: Int32
  public var stdout: String
  public var stderr: String
  public var succeeded: Bool { terminationStatus == 0 }
}

public enum ProcessRunnerError: Error, LocalizedError {
  case executableMustBeAbsolute(String)
  case workingDirectoryUnavailable(String)
  public var errorDescription: String? {
    switch self {
    case .executableMustBeAbsolute(let path): "Executable path must be absolute: \(path)"
    case .workingDirectoryUnavailable(let path): "Working directory is unavailable: \(path)"
    }
  }
}

private final class ProcessStreamCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()
  private let stream: ProcessEvent.Stream
  private let onEvent: (@Sendable (ProcessEvent) -> Void)?
  private let maximumBytes: Int
  private var truncated = false

  init(
    stream: ProcessEvent.Stream, maximumBytes: Int,
    onEvent: (@Sendable (ProcessEvent) -> Void)?
  ) {
    self.stream = stream
    self.maximumBytes = maximumBytes
    self.onEvent = onEvent
  }

  func consume(_ chunk: Data) {
    guard !chunk.isEmpty else { return }
    let accepted = lock.withLock { () -> Data in
      guard data.count < maximumBytes else {
        truncated = true
        return Data()
      }
      let prefix = chunk.prefix(maximumBytes - data.count)
      let accepted = Data(prefix)
      data.append(accepted)
      if prefix.count < chunk.count { truncated = true }
      return accepted
    }
    guard !accepted.isEmpty else { return }
    onEvent?(.init(stream: stream, text: String(decoding: accepted, as: UTF8.self)))
  }

  func snapshot() -> Data {
    lock.withLock {
      guard truncated else { return data }
      var result = data
      result.append(Data("\n[lys: output truncated]\n".utf8))
      return result
    }
  }
}

private final class ProcessEscalator: @unchecked Sendable {
  let process: Process
  init(_ process: Process) { self.process = process }
  func interruptThenTerminate() {
    process.interrupt()
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [process] in
      if process.isRunning { process.terminate() }
    }
  }
}

public actor ProcessRunner {
  private var active: [UUID: Process] = [:]
  public init() {}

  public func run(
    executable: URL, arguments: [String], workingDirectory: URL? = nil,
    environment: [String: String] = [:], maximumOutputBytes: Int = 16 * 1_024 * 1_024,
    onEvent: (@Sendable (ProcessEvent) -> Void)? = nil
  ) async throws -> ProcessOutcome {
    guard executable.path.hasPrefix("/") else {
      throw ProcessRunnerError.executableMustBeAbsolute(executable.path)
    }
    if let workingDirectory, !FileManager.default.fileExists(atPath: workingDirectory.path) {
      throw ProcessRunnerError.workingDirectoryUnavailable(workingDirectory.path)
    }
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    let id = UUID()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    process.standardOutput = output
    process.standardError = errors
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, task in task
    }
    active[id] = process
    onEvent?(.init(stream: .lifecycle, text: "started"))
    let outputCollector = ProcessStreamCollector(
      stream: .stdout, maximumBytes: maximumOutputBytes, onEvent: onEvent)
    let errorCollector = ProcessStreamCollector(
      stream: .stderr, maximumBytes: maximumOutputBytes, onEvent: onEvent)
    output.fileHandleForReading.readabilityHandler = { handle in
      let chunk = handle.availableData
      if chunk.isEmpty { handle.readabilityHandler = nil } else { outputCollector.consume(chunk) }
    }
    errors.fileHandleForReading.readabilityHandler = { handle in
      let chunk = handle.availableData
      if chunk.isEmpty { handle.readabilityHandler = nil } else { errorCollector.consume(chunk) }
    }
    do {
      try process.run()
    } catch {
      output.fileHandleForReading.readabilityHandler = nil
      errors.fileHandleForReading.readabilityHandler = nil
      active[id] = nil
      throw error
    }
    let escalator = ProcessEscalator(process)
    await withTaskCancellationHandler {
      if process.isRunning {
        await withCheckedContinuation { continuation in
          process.terminationHandler = { _ in continuation.resume() }
        }
      }
    } onCancel: {
      escalator.interruptThenTerminate()
    }
    output.fileHandleForReading.readabilityHandler = nil
    errors.fileHandleForReading.readabilityHandler = nil
    outputCollector.consume(output.fileHandleForReading.readDataToEndOfFile())
    errorCollector.consume(errors.fileHandleForReading.readDataToEndOfFile())
    let outputData = outputCollector.snapshot()
    let errorData = errorCollector.snapshot()
    let stdout = String(decoding: outputData, as: UTF8.self)
    let stderr = String(decoding: errorData, as: UTF8.self)
    active[id] = nil
    onEvent?(.init(stream: .lifecycle, text: "finished:\(process.terminationStatus)"))
    return .init(terminationStatus: process.terminationStatus, stdout: stdout, stderr: stderr)
  }

  public func cancelAll() async {
    let processes = Array(active.values)
    for process in processes { process.interrupt() }
    try? await Task.sleep(for: .seconds(5))
    for process in processes where process.isRunning { process.terminate() }
  }
}
