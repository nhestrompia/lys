import Foundation

private struct DevelopmentLaunchContext: Sendable {
  var udid: String
  var appPath: String
  var bundleID: String
}

public actor RuntimeService {
  public let workspace: URL
  public let token: String
  private let runner = ProcessRunner()
  private let devServerRunner = ProcessRunner()
  private let ledger = EvidenceLedger()
  private let wda: WDAController
  private var lastLaunchedBundleID: String?
  private var devServerTask: Task<ProcessOutcome, Error>?
  private var devServerRunID: UUID?
  private var devServerExitDiagnostic: String?
  private var devServerProjectRoot: URL?
  private var devServerShouldStayRunning = false
  private var devServerRecoveryTask: Task<Void, Never>?
  private var lastDevelopmentLaunch: DevelopmentLaunchContext?
  public init(workspace: URL, token: String) {
    self.workspace = workspace.standardizedFileURL
    self.token = token
    let support =
      (try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
        create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    wda = WDAController(
      stateRoot: support.appending(
        path: "IOSDevWorkbench/WebDriverAgent", directoryHint: .isDirectory))
  }

  public func handle(_ request: RPCEnvelope, authenticated: inout Bool) async -> RPCEnvelope {
    guard let method = request.method else { return failure(request.id, -32600, "Invalid request") }
    if method == "runtime.authenticate" {
      guard request.params?["token"]?.stringValue == token else {
        return failure(request.id, -32001, "Authentication failed")
      }
      authenticated = true
      return success(request.id, .object(["protocolVersion": .number(1)]))
    }
    guard authenticated else { return failure(request.id, -32000, "Authenticate first") }
    do {
      switch method {
      case "workspace.describe":
        return success(
          request.id, .object(["root": .string(workspace.path), "writable": .bool(true)]))
      case "workspace.mutated":
        return success(request.id, .object(["generation": .number(Double(await ledger.mutate()))]))
      case "toolchain.preflight":
        return success(request.id, try jsonValue(await ToolchainDiscovery.preflight()))
      case "project.discover":
        return success(
          request.id,
          .array(ToolchainDiscovery.projectContainers(in: workspace).map { .string($0.path) }))
      case "project.list":
        return await listProject(request)
      case "target.discover":
        return await discoverTargets(request)
      case "simulator.list":
        let preflight = await ToolchainDiscovery.preflight()
        guard let path = preflight.simctlPath, let developer = preflight.developerDirectory else {
          return failure(request.id, -32050, "Full Xcode is unavailable")
        }
        return success(
          request.id,
          try jsonValue(
            try await ToolchainDiscovery.simulators(
              simctl: URL(fileURLWithPath: path),
              developerDirectory: URL(fileURLWithPath: developer))))
      case "simulator.boot":
        guard let udid = request.params?["udid"]?.stringValue else {
          return failure(request.id, -32602, "udid is required")
        }
        return await bootSimulator(request, udid: udid)
      case "simulator.shutdown":
        guard let udid = request.params?["udid"]?.stringValue else {
          return failure(request.id, -32602, "udid is required")
        }
        return await runSimulator(
          request, make: { AppleCommandBuilder.shutdown(simctl: $0, udid: udid) },
          evidenceKind: .runtimeLog)
      case "simulator.configure":
        guard let udid = request.params?["udid"]?.stringValue,
          let appearance = request.params?["appearance"]?.stringValue,
          let value = SimulatorAppearance(rawValue: appearance)
        else { return failure(request.id, -32602, "udid and a light/dark appearance are required") }
        return await runSimulator(
          request, make: { AppleCommandBuilder.appearance(simctl: $0, udid: udid, value: value) },
          evidenceKind: .uiAction)
      case "devserver.start":
        return await startDevelopmentServer(request)
      case "devserver.status":
        return success(request.id, await developmentServerStatus())
      case "devserver.stop":
        await stopDevelopmentServer()
        return success(request.id, .object(["running": .bool(false)]))
      case "app.install_launch":
        return await installLaunch(request)
      case "app.terminate":
        guard let udid = request.params?["udid"]?.stringValue,
          let bundleID = request.params?["bundleID"]?.stringValue
        else { return failure(request.id, -32602, "udid and bundleID are required") }
        return await runSimulator(
          request,
          make: { AppleCommandBuilder.terminate(simctl: $0, udid: udid, bundleID: bundleID) },
          evidenceKind: .runtimeLog)
      case "app.reset_data":
        guard let udid = request.params?["udid"]?.stringValue,
          let bundleID = request.params?["bundleID"]?.stringValue
        else { return failure(request.id, -32602, "udid and bundleID are required") }
        guard request.params?["approved"] == .bool(true) else {
          return failure(
            request.id, -32080, "Explicit approval is required before erasing app data")
        }
        return await runSimulator(
          request,
          make: { AppleCommandBuilder.resetAppData(simctl: $0, udid: udid, bundleID: bundleID) },
          evidenceKind: .runtimeLog)
      case "screenshot.capture":
        guard let udid = request.params?["udid"]?.stringValue else {
          return failure(request.id, -32602, "udid is required")
        }
        return await captureStableScreenshot(request, udid: udid)
      case "preview.capture":
        guard let udid = request.params?["udid"]?.stringValue else {
          return failure(request.id, -32602, "udid is required")
        }
        return await capturePreviewFrame(request, udid: udid)
      case "build.run":
        return await build(request)
      case "build.cancel":
        await runner.cancelAll()
        return success(request.id, .object(["cancelled": .bool(true)]))
      case "test.list":
        return await listTests(request)
      case "test.run":
        return await test(request)
      case "logs.query":
        return await queryLogs(request)
      case "verification.status":
        let report = await ledger.verify(requirement(from: request.params))
        return success(request.id, try jsonValue(report))
      case "evidence.list":
        return success(request.id, try jsonValue(await ledger.allEvidence()))
      case "verification.submit":
        return await submitVerification(request)
      case "ui.snapshot": return await uiSnapshot(request)
      case "ui.prepare": return await uiPrepare(request)
      case "ui.find": return await uiFind(request)
      case "ui.perform": return await uiPerform(request)
      case "ui.wait": return await uiWait(request)
      case "ui.assert": return await uiAssert(request)
      case "ui.navigate":
        return failure(request.id, -32081, "No currently valid App Graph path is available")
      default: return failure(request.id, -32601, "Unknown runtime method: \(method)")
      }
    } catch { return failure(request.id, -32603, error.localizedDescription) }
  }

  private func build(_ request: RPCEnvelope) async -> RPCEnvelope {
    await xcodeAction(request, action: "build", evidenceKind: .build)
  }

  private func test(_ request: RPCEnvelope) async -> RPCEnvelope {
    await xcodeAction(request, action: "test", evidenceKind: .test)
  }

  private func xcodeAction(
    _ request: RPCEnvelope, action: String, evidenceKind: EvidenceKind
  ) async -> RPCEnvelope {
    let preflight = await ToolchainDiscovery.preflight()
    guard let xcodebuild = preflight.xcodebuildPath, let developer = preflight.developerDirectory
    else { return failure(request.id, -32050, "Select full Xcode 26.5 before building") }
    guard let container = request.params?["container"]?.stringValue,
      let scheme = request.params?["scheme"]?.stringValue,
      let destination = request.params?["destination"]?.stringValue
    else { return failure(request.id, -32602, "container, scheme, and destination are required") }
    if let requirement = CocoaPodsSupport.missingInstallation(
      for: URL(fileURLWithPath: container))
    {
      return failure(
        request.id, -32059,
        "CocoaPods dependencies are not installed for \(requirement.projectDirectory.path). \(requirement.reason) Approve CocoaPods installation in Operate, or run `pod \(requirement.installArguments.joined(separator: " "))` in that directory."
      )
    }
    do {
      let generation = await ledger.generation
      let resultPath = workspace.appending(
        path: ".iosdev/artifacts/build-\(UUID().uuidString).xcresult")
      let derived = workspace.appending(path: ".iosdev/cache/DerivedData")
      try FileManager.default.createDirectory(
        at: resultPath.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
      let flag = container.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
      let outcome = try await runner.run(
        executable: URL(fileURLWithPath: xcodebuild),
        arguments: [
          flag, container, "-scheme", scheme, "-configuration",
          request.params?["configuration"]?.stringValue ?? "Debug", "-destination", destination,
          "-derivedDataPath", derived.path, "-resultBundlePath", resultPath.path, action,
        ], workingDirectory: workspace, environment: ["DEVELOPER_DIR": developer])
      let item = Evidence(
        kind: evidenceKind, status: outcome.succeeded ? .passed : .failed,
        taskGeneration: generation,
        artifactPaths: [resultPath.path],
        diagnosticSummary: outcome.succeeded ? "xcodebuild \(action) completed" : outcome.stderr)
      try await ledger.record(item)
      return success(
        request.id,
        .object([
          "succeeded": .bool(outcome.succeeded),
          "evidenceIDs": .array([.string(item.id.uuidString)]),
          "log": .string(outcome.stdout + outcome.stderr),
        ]))
    } catch { return failure(request.id, -32052, error.localizedDescription) }
  }

  private func uiSnapshot(_ request: RPCEnvelope) async -> RPCEnvelope {
    do {
      let context = try await automationContext(request)
      let elements = try await wda.snapshot(
        udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
        preflight: context.preflight)
      return success(
        request.id,
        .object([
          "elements": try jsonValue(elements),
          "fingerprint": try jsonValue(
            ScreenFingerprint.make(elements: elements, modal: false, navigationTitle: nil)),
        ]))
    } catch let error as RPCError { return failure(request.id, error.code, error.message) } catch {
      return failure(request.id, -32077, error.localizedDescription)
    }
  }

  private func uiPrepare(_ request: RPCEnvelope) async -> RPCEnvelope {
    do {
      let context = try await automationContext(request)
      try await wda.prepare(
        udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
        preflight: context.preflight)
      return success(request.id, .object(["ready": .bool(true)]))
    } catch let error as RPCError {
      return failure(request.id, error.code, error.message)
    } catch {
      return failure(request.id, -32077, error.localizedDescription)
    }
  }

  private func uiFind(_ request: RPCEnvelope) async -> RPCEnvelope {
    do {
      let context = try await automationContext(request)
      let elements = try await wda.snapshot(
        udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
        preflight: context.preflight)
      let identifier = selectorIdentifier(request.params)
      let label =
        request.params?["selector"]?["label"]?.stringValue
        ?? request.params?["label"]?.stringValue
      let type =
        request.params?["selector"]?["type"]?.stringValue
        ?? request.params?["type"]?.stringValue
      let matches = elements.filter { element in
        (identifier == nil || element.identifier == identifier)
          && (label == nil || element.label == label)
          && (type == nil || element.type == type)
      }
      return success(request.id, .object(["elements": try jsonValue(matches)]))
    } catch let error as RPCError { return failure(request.id, error.code, error.message) } catch {
      return failure(request.id, -32077, error.localizedDescription)
    }
  }

  private func uiPerform(_ request: RPCEnvelope) async -> RPCEnvelope {
    do {
      guard let action = request.params?["action"]?.stringValue else {
        return failure(request.id, -32602, "action is required")
      }
      let identifier = selectorIdentifier(request.params)
      let label = selectorLabel(request.params)
      let type = selectorType(request.params)
      let coordinate = selectorCoordinate(request.params)
      let swipe = selectorSwipe(request.params)
      guard identifier != nil || label != nil || coordinate != nil || swipe != nil else {
        return failure(
          request.id, -32602, "selector identifier, label, or coordinate gesture is required")
      }
      let context = try await automationContext(request)
      if let coordinate {
        guard action == "tap" else {
          return failure(request.id, -32602, "Coordinate selectors support tap only")
        }
        try await wda.performCoordinateTap(
          udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
          normalizedX: coordinate.x, normalizedY: coordinate.y, preflight: context.preflight)
        // Coordinate gestures are exploratory control, not verification proof.
        // The preview footer and activity state are the user-facing trace for them.
        return success(request.id, .object(["deterministic": .bool(false)]))
      }
      if let swipe {
        guard action == "swipe" else {
          return failure(request.id, -32602, "Coordinate gestures support swipe only")
        }
        try await wda.performCoordinateSwipe(
          udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
          startX: swipe.startX, startY: swipe.startY, endX: swipe.endX, endY: swipe.endY,
          durationMS: swipe.durationMS, preflight: context.preflight)
        return success(request.id, .object(["deterministic": .bool(false)]))
      }
      let before = try await wda.snapshot(
        udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
        preflight: context.preflight)
      let beforeMatches = before.filter {
        (identifier == nil || $0.identifier == identifier)
          && (label == nil || $0.label == label)
          && (type == nil || $0.type == type)
      }
      guard beforeMatches.count == 1 else {
        return failure(
          request.id, -32078,
          beforeMatches.isEmpty
            ? "No accessibility element matches the selector"
            : "The selector is ambiguous; add an accessibility identifier")
      }
      try await wda.perform(
        udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
        identifier: identifier, label: label, type: type, action: action,
        text: request.params?["text"]?.stringValue,
        preflight: context.preflight)
      let selectorSummary =
        identifier.map { "accessibility identifier \($0)" }
        ?? "unique \(type ?? "element") label \(label ?? "")"
      var after = try await wda.snapshot(
        udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
        preflight: context.preflight)
      for _ in 0..<10 {
        try await Task.sleep(for: .milliseconds(150))
        let next = try await wda.snapshot(
          udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
          preflight: context.preflight)
        if ScreenFingerprint.make(elements: after, modal: false, navigationTitle: nil)
          == ScreenFingerprint.make(elements: next, modal: false, navigationTitle: nil)
        {
          after = next
          break
        }
        after = next
      }
      let item = Evidence(
        kind: .uiAction, status: .passed, taskGeneration: await ledger.generation,
        destinationUDID: context.udid,
        diagnosticSummary: "Deterministic \(action) using \(selectorSummary)",
        deterministic: true)
      try await ledger.record(item)
      return success(
        request.id,
        .object([
          "evidenceIDs": .array([.string(item.id.uuidString)]),
          "beforeFingerprint": try jsonValue(
            ScreenFingerprint.make(elements: before, modal: false, navigationTitle: nil)),
          "afterFingerprint": try jsonValue(
            ScreenFingerprint.make(elements: after, modal: false, navigationTitle: nil)),
          "elements": try jsonValue(after),
        ]))
    } catch let error as RPCError { return failure(request.id, error.code, error.message) } catch {
      return failure(request.id, -32077, error.localizedDescription)
    }
  }

  private func uiAssert(_ request: RPCEnvelope) async -> RPCEnvelope {
    do {
      let identifier = selectorIdentifier(request.params)
      let label = selectorLabel(request.params)
      let type = selectorType(request.params)
      guard identifier != nil || label != nil else {
        return failure(request.id, -32602, "selector identifier or label is required")
      }
      let context = try await automationContext(request)
      let elements = try await wda.snapshot(
        udid: context.udid, runtime: context.runtime, bundleID: context.bundleID,
        preflight: context.preflight)
      let matches = elements.filter {
        (identifier == nil || $0.identifier == identifier)
          && (label == nil || $0.label == label)
          && (type == nil || $0.type == type)
      }
      let found = matches.count == 1
      let selectorSummary = identifier ?? [type, label].compactMap { $0 }.joined(separator: " · ")
      let item = Evidence(
        kind: .uiAssertion, status: found ? .passed : .failed,
        taskGeneration: await ledger.generation,
        criterionID: request.params?["criterionID"]?.stringValue,
        destinationUDID: context.udid,
        diagnosticSummary: found
          ? "Found \(selectorSummary)"
          : (matches.isEmpty ? "Missing \(selectorSummary)" : "Ambiguous \(selectorSummary)"),
        deterministic: true)
      try await ledger.record(item)
      return success(
        request.id,
        .object([
          "passed": .bool(found), "evidenceIDs": .array([.string(item.id.uuidString)]),
        ]))
    } catch let error as RPCError { return failure(request.id, error.code, error.message) } catch {
      return failure(request.id, -32077, error.localizedDescription)
    }
  }

  private func uiWait(_ request: RPCEnvelope) async -> RPCEnvelope {
    let timeout = min(max(request.params?["timeoutSeconds"]?.numberValue ?? 5, 0.2), 30)
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    while ContinuousClock.now < deadline {
      let response = await uiFind(request)
      if case .object(let result) = response.result,
        case .array(let values) = result["elements"], !values.isEmpty
      {
        return response
      }
      try? await Task.sleep(for: .milliseconds(200))
    }
    return failure(request.id, -32082, "Timed out waiting for the UI selector")
  }

  private func automationContext(_ request: RPCEnvelope) async throws -> (
    udid: String, runtime: String, bundleID: String, preflight: ToolchainPreflight
  ) {
    guard let udid = request.params?["udid"]?.stringValue else {
      throw RPCError(code: -32602, message: "udid is required")
    }
    guard let bundleID = request.params?["bundleID"]?.stringValue ?? lastLaunchedBundleID else {
      throw RPCError(code: -32602, message: "bundleID is required before the first UI session")
    }
    let preflight = await ToolchainDiscovery.preflight()
    guard let simctl = preflight.simctlPath, let developer = preflight.developerDirectory else {
      throw RPCError(code: -32050, message: "Full Xcode is unavailable")
    }
    let destinations = try await ToolchainDiscovery.simulators(
      simctl: URL(fileURLWithPath: simctl), developerDirectory: URL(fileURLWithPath: developer))
    guard let runtime = destinations.first(where: { $0.udid == udid })?.runtime else {
      throw RPCError(code: -32051, message: "The selected Simulator is unavailable")
    }
    return (udid, runtime, bundleID, preflight)
  }

  private func selectorIdentifier(_ params: JSONValue?) -> String? {
    params?["selector"]?["identifier"]?.stringValue
      ?? params?["selector"]?["accessibilityIdentifier"]?.stringValue
      ?? params?["identifier"]?.stringValue
  }

  private func selectorLabel(_ params: JSONValue?) -> String? {
    params?["selector"]?["label"]?.stringValue ?? params?["label"]?.stringValue
  }

  private func selectorType(_ params: JSONValue?) -> String? {
    params?["selector"]?["type"]?.stringValue ?? params?["type"]?.stringValue
  }

  private func selectorCoordinate(_ params: JSONValue?) -> (x: Double, y: Double)? {
    guard let x = params?["selector"]?["coordinate"]?["x"]?.numberValue,
      let y = params?["selector"]?["coordinate"]?["y"]?.numberValue
    else { return nil }
    return (min(max(x, 0), 1), min(max(y, 0), 1))
  }

  private func selectorSwipe(_ params: JSONValue?) -> (
    startX: Double, startY: Double, endX: Double, endY: Double, durationMS: Int
  )? {
    guard let coordinate = params?["selector"]?["coordinate"],
      let startX = coordinate["startX"]?.numberValue,
      let startY = coordinate["startY"]?.numberValue,
      let endX = coordinate["endX"]?.numberValue,
      let endY = coordinate["endY"]?.numberValue
    else { return nil }
    let durationMS = Int(coordinate["durationMS"]?.numberValue ?? 350)
    return (
      min(max(startX, 0), 1), min(max(startY, 0), 1), min(max(endX, 0), 1),
      min(max(endY, 0), 1), durationMS)
  }

  private func listTests(_ request: RPCEnvelope) async -> RPCEnvelope {
    guard let container = request.params?["container"]?.stringValue,
      let scheme = request.params?["scheme"]?.stringValue
    else { return failure(request.id, -32602, "container and scheme are required") }
    let preflight = await ToolchainDiscovery.preflight()
    guard let path = preflight.xcodebuildPath, let developer = preflight.developerDirectory else {
      return failure(request.id, -32050, "Full Xcode is unavailable")
    }
    let flag = container.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
    do {
      let outcome = try await runner.run(
        executable: URL(fileURLWithPath: path),
        arguments: [flag, container, "-scheme", scheme, "-showTestPlans"],
        workingDirectory: workspace, environment: ["DEVELOPER_DIR": developer],
        maximumOutputBytes: 1_024 * 1_024)
      guard outcome.succeeded else { return failure(request.id, -32057, outcome.stderr) }
      let plans = outcome.stdout.split(separator: "\n").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }.filter { !$0.isEmpty && !$0.hasPrefix("Test plans associated") }
      return success(request.id, .object(["testPlans": .array(plans.map(JSONValue.string))]))
    } catch { return failure(request.id, -32057, error.localizedDescription) }
  }

  private func queryLogs(_ request: RPCEnvelope) async -> RPCEnvelope {
    guard let udid = request.params?["udid"]?.stringValue,
      let process = request.params?["process"]?.stringValue, !process.isEmpty
    else { return failure(request.id, -32602, "udid and process are required") }
    let requested = Int(request.params?["seconds"]?.numberValue ?? 300)
    let seconds = min(max(requested, 1), 3_600)
    let preflight = await ToolchainDiscovery.preflight()
    guard let path = preflight.simctlPath, let developer = preflight.developerDirectory else {
      return failure(request.id, -32050, "Full Xcode is unavailable")
    }
    do {
      let spec = AppleCommandBuilder.logQuery(
        simctl: URL(fileURLWithPath: path), udid: udid, process: process, seconds: seconds)
      let outcome = try await runner.run(
        executable: spec.executable, arguments: spec.arguments, workingDirectory: workspace,
        environment: ["DEVELOPER_DIR": developer], maximumOutputBytes: 4 * 1_024 * 1_024)
      let artifact = workspace.appending(path: ".iosdev/artifacts/log-\(UUID().uuidString).txt")
      try FileManager.default.createDirectory(
        at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true)
      let contents = outcome.stdout + outcome.stderr
      try Data(contents.utf8).write(to: artifact, options: .atomic)
      let item = Evidence(
        kind: .runtimeLog, status: outcome.succeeded ? .passed : .failed,
        taskGeneration: await ledger.generation, destinationUDID: udid,
        artifactPaths: [artifact.path],
        diagnosticSummary: outcome.succeeded ? "\(seconds)s log query" : outcome.stderr)
      try await ledger.record(item)
      return success(
        request.id,
        .object([
          "log": .string(contents), "evidenceIDs": .array([.string(item.id.uuidString)]),
          "seconds": .number(Double(seconds)),
        ]))
    } catch { return failure(request.id, -32058, error.localizedDescription) }
  }

  private func listProject(_ request: RPCEnvelope) async -> RPCEnvelope {
    guard let containerPath = request.params?["container"]?.stringValue else {
      return failure(request.id, -32602, "container is required")
    }
    let preflight = await ToolchainDiscovery.preflight()
    guard let path = preflight.xcodebuildPath, let developer = preflight.developerDirectory else {
      return failure(request.id, -32050, "Full Xcode is unavailable")
    }
    do {
      let listing = try await ToolchainDiscovery.listProject(
        container: URL(fileURLWithPath: containerPath), xcodebuild: URL(fileURLWithPath: path),
        developerDirectory: URL(fileURLWithPath: developer))
      return success(request.id, try jsonValue(listing))
    } catch { return failure(request.id, -32055, error.localizedDescription) }
  }

  private func discoverTargets(_ request: RPCEnvelope) async -> RPCEnvelope {
    guard let containerPath = request.params?["container"]?.stringValue,
      let scheme = request.params?["scheme"]?.stringValue,
      let destination = request.params?["destination"]?.stringValue
    else { return failure(request.id, -32602, "container, scheme, and destination are required") }
    let preflight = await ToolchainDiscovery.preflight()
    guard let path = preflight.xcodebuildPath, let developer = preflight.developerDirectory else {
      return failure(request.id, -32050, "Full Xcode is unavailable")
    }
    do {
      let targets = try await ToolchainDiscovery.appTargets(
        container: URL(fileURLWithPath: containerPath), scheme: scheme,
        configuration: request.params?["configuration"]?.stringValue ?? "Debug",
        destination: destination, xcodebuild: URL(fileURLWithPath: path),
        developerDirectory: URL(fileURLWithPath: developer),
        derivedData: workspace.appending(path: ".iosdev/cache/DerivedData"))
      return success(request.id, try jsonValue(targets))
    } catch { return failure(request.id, -32055, error.localizedDescription) }
  }

  private func submitVerification(_ request: RPCEnvelope) async -> RPCEnvelope {
    let submitted = Set(
      request.params?["evidenceIDs"]?.arrayValue?.compactMap { $0.stringValue } ?? [])
    let available = await ledger.allEvidence()
    let availableIDs = Set(available.map { $0.id.uuidString })
    let unknown = submitted.subtracting(availableIDs).sorted()
    guard unknown.isEmpty else {
      return failure(
        request.id, -32021,
        "Verification manifest references unknown evidence IDs: \(unknown.joined(separator: ", "))")
    }
    let report = await ledger.verify(requirement(from: request.params))
    return success(request.id, (try? jsonValue(report)) ?? .null)
  }

  private func installLaunch(_ request: RPCEnvelope) async -> RPCEnvelope {
    guard let udid = request.params?["udid"]?.stringValue,
      let appPath = request.params?["appPath"]?.stringValue,
      let bundleID = request.params?["bundleID"]?.stringValue
    else { return failure(request.id, -32602, "udid, appPath, and bundleID are required") }
    let shouldStartDevServer = request.params?["startDevServer"]?.boolValue ?? isExpoWorkspace
    let shouldUseDevServer = request.params?["useDevServer"]?.boolValue ?? shouldStartDevServer
    if shouldStartDevServer {
      let started = await startDevelopmentServer(request)
      if let error = started.error { return failure(request.id, error.code, error.message) }
    }
    if shouldUseDevServer, !(await isDevelopmentServerReady(port: 8081)) {
      return failure(
        request.id, -32099,
        "Metro is not reachable on port 8081. Start the selected project's development server and try Run again."
      )
    }
    let preflight = await ToolchainDiscovery.preflight()
    guard let path = preflight.simctlPath, let developer = preflight.developerDirectory else {
      return failure(request.id, -32050, "Full Xcode is unavailable")
    }
    let simctl = URL(fileURLWithPath: path)
    let environment = ["DEVELOPER_DIR": developer]
    do {
      let install = AppleCommandBuilder.install(
        simctl: simctl, udid: udid, app: URL(fileURLWithPath: appPath))
      let installed = try await runner.run(
        executable: install.executable, arguments: install.arguments, workingDirectory: workspace,
        environment: environment)
      guard installed.succeeded else { return failure(request.id, -32053, installed.stderr) }
      if shouldUseDevServer {
        for command in AppleCommandBuilder.configureMetro(
          simctl: simctl, udid: udid, bundleID: bundleID)
        {
          let configured = try await runner.run(
            executable: command.executable, arguments: command.arguments,
            workingDirectory: workspace, environment: environment)
          guard configured.succeeded else {
            return failure(
              request.id, -32053,
              "Could not configure the app's Metro endpoint: \(configured.stderr)")
          }
        }
      }
      let launchArguments =
        shouldUseDevServer
        ? ["-RCT_jsLocation", "127.0.0.1:8081", "-RCT_enableDev", "YES"] : []
      let launch = AppleCommandBuilder.launch(
        simctl: simctl, udid: udid, bundleID: bundleID, arguments: launchArguments)
      let launched = try await runner.run(
        executable: launch.executable, arguments: launch.arguments, workingDirectory: workspace,
        environment: environment)
      let item = Evidence(
        kind: .launch, status: launched.succeeded ? .passed : .failed,
        taskGeneration: await ledger.generation, destinationUDID: udid,
        diagnosticSummary: launched.succeeded ? launched.stdout : launched.stderr)
      try await ledger.record(item)
      if launched.succeeded { lastLaunchedBundleID = bundleID }
      if launched.succeeded, shouldUseDevServer {
        lastDevelopmentLaunch = .init(udid: udid, appPath: appPath, bundleID: bundleID)
      }
      return success(
        request.id,
        .object([
          "launched": .bool(launched.succeeded),
          "evidenceIDs": .array([.string(item.id.uuidString)]),
        ]))
    } catch { return failure(request.id, -32053, error.localizedDescription) }
  }

  private func startDevelopmentServer(_ request: RPCEnvelope) async -> RPCEnvelope {
    let port = Int(request.params?["port"]?.numberValue ?? 8081)
    guard port == 8081 else {
      return failure(request.id, -32602, "The public alpha currently supports Metro on port 8081")
    }
    guard let projectRoot = expoProjectRoot(from: request.params) else {
      return failure(request.id, -32096, "This workspace is not an Expo project")
    }
    if devServerTask != nil,
      devServerProjectRoot?.standardizedFileURL != projectRoot.standardizedFileURL
    {
      await stopDevelopmentServer()
    }
    devServerShouldStayRunning = true
    if await isDevelopmentServerReady(port: port) {
      if devServerTask == nil {
        let owner = await developmentServerOwnerWorkspace(port: port)
        guard owner?.standardizedFileURL == projectRoot.standardizedFileURL else {
          return failure(
            request.id, -32099,
            "Port 8081 is serving a different project\(owner.map { " at \($0.path)" } ?? "")")
        }
      }
      return success(
        request.id,
        .object([
          "running": .bool(true), "port": .number(Double(port)),
          "managed": .bool(devServerTask != nil),
          "detail": .string(
            devServerTask == nil
              ? "Reusing a development server already listening on port 8081"
              : "Metro is ready for \(projectRoot.lastPathComponent)"),
        ]))
    }
    guard let npm = npmExecutable else {
      return failure(request.id, -32097, "npm was not found; install Node.js and try again")
    }

    if devServerTask == nil {
      devServerExitDiagnostic = nil
      devServerProjectRoot = projectRoot
      let runID = UUID()
      devServerRunID = runID
      let searchPath = executableSearchPath
      let task = Task.detached { [devServerRunner] in
        try await devServerRunner.run(
          executable: npm, arguments: ["start", "--", "--port", String(port)],
          workingDirectory: projectRoot,
          environment: ["PATH": searchPath, "BROWSER": "none", "CI": "1"],
          maximumOutputBytes: 8 * 1_024 * 1_024)
      }
      devServerTask = task
      Task { [weak self] in
        let result = await task.result
        await self?.developmentServerDidExit(runID: runID, result: result)
      }
    }

    for _ in 0..<120 {
      if await isDevelopmentServerReady(port: port) {
        return success(
          request.id,
          .object([
            "running": .bool(true), "managed": .bool(true),
            "port": .number(Double(port)),
            "detail": .string("Metro is serving \(projectRoot.lastPathComponent)"),
          ]))
      }
      if let devServerExitDiagnostic {
        await stopDevelopmentServer(resetIntent: false)
        return failure(
          request.id, -32098,
          "Metro exited before it became ready: \(devServerExitDiagnostic)")
      }
      try? await Task.sleep(for: .milliseconds(250))
    }
    await stopDevelopmentServer(resetIntent: false)
    return failure(request.id, -32099, "Metro did not become ready within 30 seconds")
  }

  private func developmentServerStatus() async -> JSONValue {
    let ready = await isDevelopmentServerReady(port: 8081)
    return .object([
      "running": .bool(ready), "managed": .bool(devServerTask != nil),
      "port": .number(8081),
      "detail": .string(
        ready ? "Metro is listening on port 8081" : "No Metro server is ready on port 8081"),
    ])
  }

  private func stopDevelopmentServer(resetIntent: Bool = true) async {
    if resetIntent {
      devServerShouldStayRunning = false
      devServerRecoveryTask?.cancel()
      devServerRecoveryTask = nil
      lastDevelopmentLaunch = nil
    }
    guard let task = devServerTask else {
      devServerRunID = nil
      devServerExitDiagnostic = nil
      devServerProjectRoot = nil
      return
    }
    devServerTask = nil
    devServerRunID = nil
    devServerExitDiagnostic = nil
    devServerProjectRoot = nil
    task.cancel()
    _ = await task.result
  }

  private func developmentServerDidExit(
    runID: UUID, result: Result<ProcessOutcome, Error>
  ) {
    guard devServerRunID == runID else { return }
    switch result {
    case .success(let outcome):
      let diagnostic = outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      devServerExitDiagnostic =
        diagnostic.isEmpty
        ? "process exited with status \(outcome.terminationStatus)" : diagnostic
    case .failure(let error):
      devServerExitDiagnostic = error.localizedDescription
    }
    scheduleDevelopmentServerRecovery(runID: runID)
  }

  private func scheduleDevelopmentServerRecovery(runID: UUID) {
    guard devServerShouldStayRunning, devServerRunID == runID,
      devServerRecoveryTask == nil, let projectRoot = devServerProjectRoot
    else { return }
    devServerRecoveryTask = Task { [weak self] in
      await self?.recoverDevelopmentServer(projectRoot: projectRoot, runID: runID)
    }
  }

  private func recoverDevelopmentServer(projectRoot: URL, runID: UUID) async {
    defer { devServerRecoveryTask = nil }
    try? await Task.sleep(for: .milliseconds(600))
    guard !Task.isCancelled, devServerShouldStayRunning, devServerRunID == runID else { return }
    devServerTask = nil
    devServerRunID = nil
    devServerExitDiagnostic = nil

    for attempt in 1...3 where devServerShouldStayRunning && !Task.isCancelled {
      let restarted = await startDevelopmentServer(
        .init(
          id: nil, method: "devserver.start",
          params: .object([
            "projectPath": .string(projectRoot.path), "port": .number(8081),
          ])))
      if restarted.error == nil {
        if let launch = lastDevelopmentLaunch {
          _ = await installLaunch(
            .init(
              id: nil, method: "app.install_launch",
              params: .object([
                "udid": .string(launch.udid), "appPath": .string(launch.appPath),
                "bundleID": .string(launch.bundleID), "startDevServer": .bool(false),
                "useDevServer": .bool(true),
              ])))
        }
        return
      }
      try? await Task.sleep(for: .seconds(attempt))
    }
  }

  private func isDevelopmentServerReady(port: Int) async -> Bool {
    guard let url = URL(string: "http://127.0.0.1:\(port)/status") else { return false }
    var request = URLRequest(url: url)
    request.timeoutInterval = 0.75
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        return false
      }
      return String(decoding: data, as: UTF8.self).contains("packager-status:running")
    } catch {
      return false
    }
  }

  private var isExpoWorkspace: Bool { discoverExpoProject() != nil }

  private func expoProjectRoot(from params: JSONValue?) -> URL? {
    if let requested = params?["projectPath"]?.stringValue {
      let candidate = URL(fileURLWithPath: requested).standardizedFileURL
      guard candidate.path == workspace.path || candidate.path.hasPrefix(workspace.path + "/"),
        Self.packageUsesExpo(at: candidate)
      else { return nil }
      return candidate
    }
    return discoverExpoProject()
  }

  private func discoverExpoProject() -> URL? {
    if Self.packageUsesExpo(at: workspace) { return workspace }
    guard
      let enumerator = FileManager.default.enumerator(
        at: workspace, includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])
    else { return nil }
    while let url = enumerator.nextObject() as? URL {
      if ["node_modules", "Pods", "DerivedData", ".build"].contains(url.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }
      if url.lastPathComponent == "package.json",
        Self.packageUsesExpo(at: url.deletingLastPathComponent())
      {
        return url.deletingLastPathComponent().standardizedFileURL
      }
    }
    return nil
  }

  private static func packageUsesExpo(at directory: URL) -> Bool {
    guard let data = try? Data(contentsOf: directory.appending(path: "package.json")),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    let dependencies = root["dependencies"] as? [String: Any]
    let development = root["devDependencies"] as? [String: Any]
    return dependencies?["expo"] != nil || development?["expo"] != nil
  }

  private func developmentServerOwnerWorkspace(port: Int) async -> URL? {
    let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")
    guard FileManager.default.isExecutableFile(atPath: lsof.path),
      let listener = try? await runner.run(
        executable: lsof,
        arguments: ["-nP", "-tiTCP:\(port)", "-sTCP:LISTEN"],
        maximumOutputBytes: 64 * 1_024),
      let pid = listener.stdout.split(whereSeparator: \.isNewline).first,
      let details = try? await runner.run(
        executable: lsof, arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"],
        maximumOutputBytes: 64 * 1_024),
      let path = details.stdout.split(whereSeparator: \.isNewline).map(String.init)
        .first(where: { $0.hasPrefix("n/") })
    else { return nil }
    return URL(fileURLWithPath: String(path.dropFirst()))
  }

  private var npmExecutable: URL? {
    ["/opt/homebrew/bin/npm", "/usr/local/bin/npm", "/usr/bin/npm"]
      .map(URL.init(fileURLWithPath:))
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  private var executableSearchPath: String {
    let standard = [
      "/opt/homebrew/bin", "/usr/local/bin",
      FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
      "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]
    let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
    var seen = Set<String>()
    return (standard + inherited.split(separator: ":").map(String.init))
      .filter { !$0.isEmpty && seen.insert($0).inserted }
      .joined(separator: ":")
  }

  private func runSimulator(
    _ request: RPCEnvelope, make: (URL) -> CommandSpec, evidenceKind: EvidenceKind,
    artifact: String? = nil
  ) async -> RPCEnvelope {
    let preflight = await ToolchainDiscovery.preflight()
    guard let path = preflight.simctlPath, let developer = preflight.developerDirectory else {
      return failure(request.id, -32050, "Full Xcode is unavailable")
    }
    do {
      let spec = make(URL(fileURLWithPath: path))
      let outcome = try await runner.run(
        executable: spec.executable, arguments: spec.arguments, workingDirectory: workspace,
        environment: ["DEVELOPER_DIR": developer])
      let item = Evidence(
        kind: evidenceKind, status: outcome.succeeded ? .passed : .failed,
        taskGeneration: await ledger.generation,
        destinationUDID: request.params?["udid"]?.stringValue,
        artifactPaths: artifact.map { [$0] } ?? [],
        diagnosticSummary: outcome.succeeded ? outcome.stdout : outcome.stderr,
        deterministic: evidenceKind != .uiAction)
      try await ledger.record(item)
      return success(
        request.id,
        .object([
          "succeeded": .bool(outcome.succeeded),
          "evidenceIDs": .array([.string(item.id.uuidString)]),
          "diagnostics": .string(outcome.stdout + outcome.stderr),
        ]))
    } catch { return failure(request.id, -32054, error.localizedDescription) }
  }

  private func bootSimulator(_ request: RPCEnvelope, udid: String) async -> RPCEnvelope {
    let preflight = await ToolchainDiscovery.preflight()
    guard let path = preflight.simctlPath, let developer = preflight.developerDirectory else {
      return failure(request.id, -32050, "Full Xcode is unavailable")
    }
    let simctl = URL(fileURLWithPath: path)
    let environment = ["DEVELOPER_DIR": developer]
    do {
      let boot = AppleCommandBuilder.boot(simctl: simctl, udid: udid)
      let booted = try await runner.run(
        executable: boot.executable, arguments: boot.arguments, workingDirectory: workspace,
        environment: environment)
      let status = AppleCommandBuilder.bootStatus(simctl: simctl, udid: udid)
      let ready = try await runner.run(
        executable: status.executable, arguments: status.arguments, workingDirectory: workspace,
        environment: environment)
      let succeeded = ready.succeeded
      let detail =
        succeeded
        ? (booted.succeeded
          ? "Simulator booted and ready." : "Simulator was already booted and is ready.")
        : ready.stderr
      let item = Evidence(
        kind: .runtimeLog, status: succeeded ? .passed : .failed,
        taskGeneration: await ledger.generation, destinationUDID: udid,
        diagnosticSummary: detail)
      try await ledger.record(item)
      return success(
        request.id,
        .object([
          "succeeded": .bool(succeeded),
          "alreadyBooted": .bool(!booted.succeeded && succeeded),
          "evidenceIDs": .array([.string(item.id.uuidString)]),
          "diagnostics": .string(detail),
        ]))
    } catch { return failure(request.id, -32054, error.localizedDescription) }
  }

  private func captureStableScreenshot(_ request: RPCEnvelope, udid: String) async -> RPCEnvelope {
    let preflight = await ToolchainDiscovery.preflight()
    guard let path = preflight.simctlPath, let developer = preflight.developerDirectory else {
      return failure(request.id, -32050, "Full Xcode is unavailable")
    }
    let simctl = URL(fileURLWithPath: path)
    let environment = ["DEVELOPER_DIR": developer]
    let artifacts = workspace.appending(path: ".iosdev/artifacts", directoryHint: .isDirectory)
    let output = artifacts.appending(path: "screenshot-\(UUID().uuidString).png")
    let settleDelay = min(max(Int(request.params?["settleDelayMS"]?.numberValue ?? 0), 0), 10_000)
    var temporaryFiles: [URL] = []
    defer {
      for file in temporaryFiles { try? FileManager.default.removeItem(at: file) }
    }

    do {
      try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
      if settleDelay > 0 { try await Task.sleep(for: .milliseconds(settleDelay)) }

      var previousHash: String?
      var finalCapture: URL?
      var stable = false
      var frameCount = 0
      for attempt in 0..<8 {
        if attempt > 0 { try await Task.sleep(for: .milliseconds(350)) }
        let capture = artifacts.appending(path: ".capture-\(UUID().uuidString).png")
        temporaryFiles.append(capture)
        let command = AppleCommandBuilder.screenshot(
          simctl: simctl, udid: udid, output: capture)
        let outcome = try await runner.run(
          executable: command.executable, arguments: command.arguments,
          workingDirectory: workspace, environment: environment)
        guard outcome.succeeded else {
          let item = Evidence(
            kind: .screenshot, status: .failed, taskGeneration: await ledger.generation,
            destinationUDID: udid, diagnosticSummary: outcome.stderr)
          try await ledger.record(item)
          return success(
            request.id,
            .object([
              "succeeded": .bool(false),
              "evidenceIDs": .array([.string(item.id.uuidString)]),
              "diagnostics": .string(outcome.stderr),
            ]))
        }
        frameCount += 1
        finalCapture = capture
        let hash = try ArchiveValidator.sha256(of: capture)
        if hash == previousHash {
          stable = true
          break
        }
        previousHash = hash
      }

      guard let finalCapture else {
        return failure(request.id, -32054, "Simulator did not produce a screenshot")
      }
      try? FileManager.default.removeItem(at: output)
      try FileManager.default.copyItem(at: finalCapture, to: output)
      let summary =
        stable
        ? "Simulator settled after \(frameCount) captured frames."
        : "Captured the latest frame after the Simulator stability timeout."
      let item = Evidence(
        kind: .screenshot, status: .passed, taskGeneration: await ledger.generation,
        destinationUDID: udid, artifactPaths: [output.path], diagnosticSummary: summary)
      try await ledger.record(item)
      return success(
        request.id,
        .object([
          "succeeded": .bool(true), "stable": .bool(stable),
          "frames": .number(Double(frameCount)),
          "artifactPath": .string(output.path),
          "evidenceIDs": .array([.string(item.id.uuidString)]),
          "diagnostics": .string(summary),
        ]))
    } catch { return failure(request.id, -32054, error.localizedDescription) }
  }

  /// Captures one frame for the live preview. Unlike `screenshot.capture`, this deliberately
  /// creates no evidence and performs no stability wait; verification uses the slower path.
  private func capturePreviewFrame(_ request: RPCEnvelope, udid: String) async -> RPCEnvelope {
    let preflight = await ToolchainDiscovery.preflight()
    guard let path = preflight.simctlPath, let developer = preflight.developerDirectory else {
      return failure(request.id, -32050, "Full Xcode is unavailable")
    }
    let previewDirectory = workspace.appending(
      path: ".iosdev/cache/Preview", directoryHint: .isDirectory)
    let output = previewDirectory.appending(path: "preview-\(UUID().uuidString).png")
    let started = DispatchTime.now().uptimeNanoseconds
    do {
      try FileManager.default.createDirectory(
        at: previewDirectory, withIntermediateDirectories: true)
      let command = AppleCommandBuilder.screenshot(
        simctl: URL(fileURLWithPath: path), udid: udid, output: output)
      let outcome = try await runner.run(
        executable: command.executable, arguments: command.arguments,
        workingDirectory: workspace, environment: ["DEVELOPER_DIR": developer])
      guard outcome.succeeded else {
        return failure(request.id, -32054, outcome.stderr)
      }
      trimPreviewFrames(in: previewDirectory, keeping: 12)
      let elapsed = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
      return success(
        request.id,
        .object([
          "path": .string(output.path), "elapsedMS": .number(Double(elapsed)),
        ]))
    } catch {
      return failure(request.id, -32054, error.localizedDescription)
    }
  }

  private func trimPreviewFrames(in directory: URL, keeping limit: Int) {
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles])
    else { return }
    let frames = files.filter { $0.lastPathComponent.hasPrefix("preview-") }.sorted {
      let left =
        (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      let right =
        (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      return left > right
    }
    for file in frames.dropFirst(limit) { try? FileManager.default.removeItem(at: file) }
  }
}

private func requirement(from params: JSONValue?) -> VerificationRequirement {
  .init(
    codeChanged: params?["codeChanged"]?.boolValue ?? true,
    uiChanged: params?["uiChanged"]?.boolValue ?? false,
    testsChanged: params?["testsChanged"]?.boolValue ?? false,
    criterionIDs: params?["criterionIDs"]?.arrayValue?.compactMap { $0.stringValue } ?? [])
}

public func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
  let data = try JSONEncoder().encode(value)
  return try JSONDecoder().decode(JSONValue.self, from: data)
}
private func success(_ id: RPCID?, _ result: JSONValue) -> RPCEnvelope {
  .init(id: id, result: result)
}
private func failure(_ id: RPCID?, _ code: Int, _ message: String) -> RPCEnvelope {
  .init(id: id, error: .init(code: code, message: message))
}
