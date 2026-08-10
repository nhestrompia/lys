import AppKit
import IOSDevCore
import SwiftUI

enum PrimarySection: String, CaseIterable, Identifiable {
  case agent = "Agent"
  case code = "Code"
  case files = "Files"
  case git = "Git"
  case settings = "Settings"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .agent: "sparkles.square.filled.on.square"
    case .code: "chevron.left.forwardslash.chevron.right"
    case .files: "folder"
    case .git: "arrow.triangle.branch"
    case .settings: "gearshape"
    }
  }
}

struct FileNode: Identifiable, Hashable {
  var id: String { url.path }
  var url: URL
  var name: String { url.lastPathComponent }
  var children: [FileNode]?
}

struct TimelineItem: Identifiable {
  enum State { case complete, active, waiting, warning }
  let id = UUID()
  var time: String
  var title: String
  var detail: String
  var state: State
}

struct TaskPlanItem: Identifiable {
  enum State { case complete, active, waiting, blocked }
  let id = UUID()
  var title: String
  var state: State
}

struct AgentPermissionOption: Identifiable, Hashable {
  var id: String
  var name: String
  var kind: String
}

struct AgentPermissionRequest: Identifiable {
  let id = UUID()
  var title: String
  var detail: String
  var options: [AgentPermissionOption]
}

enum AppOperation: Equatable {
  case idle
  case preparing
  case building
  case launching
  case refreshing

  var title: String? {
    switch self {
    case .idle: nil
    case .preparing: "Preparing to build"
    case .building: "Building app"
    case .launching: "Launching app"
    case .refreshing: "Refreshing app"
    }
  }

  var detail: String? {
    switch self {
    case .idle: nil
    case .preparing: "Starting the local JavaScript development server."
    case .building: "Waiting for Xcode to finish. The preview will update after launch."
    case .launching: "Installing the latest build on the selected Simulator."
    case .refreshing: "Relaunching the installed app and capturing a fresh screenshot."
    }
  }
}

@MainActor
public final class AppModel: ObservableObject {
  @Published var section: PrimarySection = .agent
  @Published var repository: URL?
  @Published var branchName = "—"
  @Published var isGitRepository = false
  @Published var activeWorktree: URL?
  @Published var containers: [URL] = []
  @Published var selectedContainer: URL?
  @Published var schemes: [String] = []
  @Published var selectedScheme = ""
  @Published var destinations: [Destination] = []
  @Published var selectedDestinationID = ""
  @Published var selectedTarget: AppTarget?
  @Published var files: [FileNode] = []
  @Published var selectedFile: URL?
  @Published var source = ""
  @Published var preflight: ToolchainPreflight?
  @Published var developerDirectory: URL?
  @Published var status = "No project"
  @Published var generation = 0
  @Published var taskPrompt = ""
  @Published var taskTitle = ""
  @Published var timeline: [TimelineItem] = []
  @Published var plan: [TaskPlanItem] = []
  @Published var evidence: [Evidence] = []
  @Published var verificationReport: VerificationReport?
  @Published var selectedElement: UIElement?
  @Published var hierarchyElements: [UIElement] = []
  @Published var notice: String?
  @Published var proposedChanges: [ProposedChange] = []
  @Published var applyConflicts: [ApplyConflict] = []
  @Published var isBusy = false
  @Published var selectedAppearance: SimulatorAppearance = .light
  @Published var currentScreenshot: URL?
  @Published var appOperation: AppOperation = .idle
  @Published var adapters: [DetectedAdapter] = []
  @Published var selectedAdapterID = ""
  @Published var wdaStatus = WDAStatus(
    availability: .unsupported, title: "Checking semantic UI automation",
    detail: "Select Xcode and a Simulator destination.", entry: nil, cacheDirectory: nil)
  @Published var recoverableWorkspaces: [RecoverableWorkspace] = []
  @Published var designPreview = false
  @Published var pendingAgentPermission: AgentPermissionRequest?
  @Published var startDevServerOnRun = true

  var selectedDestination: Destination? {
    destinations.first { $0.udid == selectedDestinationID }
  }
  var taskWorkspace: URL? { activeWorktree ?? repository }
  var canBuild: Bool {
    repository != nil && selectedContainer != nil && !selectedScheme.isEmpty
      && selectedDestination != nil && preflight?.isFullXcode == true && !isBusy
  }
  var canRun: Bool { canBuild && taskWorkspace != nil }
  var changedFileCount: Int { proposedChanges.count }
  var isSemanticAutomationReady: Bool { wdaStatus.availability == .ready }
  var meaningfulHierarchyElements: [UIElement] {
    UIHierarchyInspector.meaningfulElements(from: hierarchyElements)
  }
  var requiresUIVerification: Bool { activeWorktree != nil && selectedTarget != nil }
  var isExpoRepository: Bool {
    guard let repository,
      let data = try? Data(contentsOf: repository.appending(path: "package.json")),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    let dependencies = root["dependencies"] as? [String: Any]
    let development = root["devDependencies"] as? [String: Any]
    return dependencies?["expo"] != nil || development?["expo"] != nil
  }
  var needsExpoPreparation: Bool { isExpoRepository && containers.isEmpty }
  var agentComposerBlocker: String? {
    if repository == nil { return "Open a Git repository to start an editable agent task." }
    if !isGitRepository { return "Agent editing requires a Git repository." }
    if selectedAdapterID.isEmpty
      || !adapters.contains(where: { $0.id == selectedAdapterID && $0.executable != nil })
    {
      return "Choose an ACP-ready agent in Settings."
    }
    if activeWorktree != nil && activeACPSessionID == nil {
      return "This recovered task has no agent session. Review or discard it before starting again."
    }
    return nil
  }
  var canSendAgentPrompt: Bool {
    !taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && agentComposerBlocker == nil && !isBusy
  }

  private var baseline: BaselineManifest?
  private let workspaceManager = WorkspaceManager()
  private let runtime = RuntimeController()
  private let runner = ProcessRunner()
  private let taskRoot: URL
  private let runtimeRoot: URL
  private let adapterRoot: URL
  private let wdaRoot: URL
  private let wdaInstaller = WDAInstaller()
  private var activeACPClient: ACPClient?
  private var activeACPSessionID: String?
  private var metroTask: Task<ProcessOutcome, Error>?
  private var metroRunID: UUID?
  private var metroWorkspace: URL?
  private var metroExitDiagnostic: String?
  private var permissionContinuation: CheckedContinuation<RPCEnvelope, Never>?
  private var pendingPermissionRPCID: RPCID?

  public init() {
    let support =
      (try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
        create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let root = support.appending(path: "IOSDevWorkbench", directoryHint: .isDirectory)
    taskRoot = root.appending(path: "Tasks", directoryHint: .isDirectory)
    runtimeRoot = root.appending(path: "Runtime", directoryHint: .isDirectory)
    adapterRoot = root.appending(path: "Adapters", directoryHint: .isDirectory)
    wdaRoot = root.appending(path: "WebDriverAgent", directoryHint: .isDirectory)
    adapters = AdapterManager.detect(managedRoot: adapterRoot)
    selectedAdapterID = adapters.first(where: { $0.executable != nil })?.id ?? ""
    Task {
      await refreshToolchain()
      await refreshRecovery()
    }
  }

  func chooseRepository() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open Repository"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    openRepository(url)
  }

  func chooseXcode() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Select Xcode"
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    guard panel.runModal() == .OK, let selected = panel.url else { return }
    let developer =
      selected.pathExtension == "app"
      ? selected.appending(path: "Contents/Developer", directoryHint: .isDirectory) : selected
    developerDirectory = developer
    Task { await refreshToolchain() }
  }

  func openRepository(_ url: URL) {
    cancelOwnedMetro()
    activeACPClient?.cancel()
    activeACPClient = nil
    activeACPSessionID = nil
    resolveAgentPermission(optionID: nil)
    repository = url.resolvingSymlinksInPath().standardizedFileURL
    activeWorktree = nil
    baseline = nil
    proposedChanges = []
    applyConflicts = []
    evidence = []
    verificationReport = nil
    currentScreenshot = nil
    appOperation = .idle
    containers = ToolchainDiscovery.projectContainers(in: url)
    selectedContainer = containers.first
    files = Self.children(of: url, depth: 0)
    selectedFile = nil
    source = ""
    taskTitle = ""
    timeline = [
      .init(time: Self.now(), title: "Repository opened", detail: url.path, state: .complete),
      .init(
        time: "—", title: "Describe a task to begin",
        detail: "Editable agent work will be isolated from this checkout.", state: .waiting),
    ]
    plan = []
    status = "Discovering"
    Task { await loadRepository() }
  }

  func selectContainer(_ url: URL) {
    selectedContainer = url
    Task { await refreshProjectSelection() }
  }

  func selectScheme(_ scheme: String) {
    selectedScheme = scheme
    selectedTarget = nil
  }

  func selectDestination(_ id: String) {
    selectedDestinationID = id
    selectedTarget = nil
    refreshWDAStatus()
  }

  func refreshSimulators() {
    Task { await refreshDestinations() }
  }

  func prepareExpoProject() {
    guard let repository, needsExpoPreparation else { return }
    let confirmation = NSAlert()
    confirmation.messageText = "Prepare this Expo project for iOS?"
    confirmation.informativeText =
      "Operate will run npm ci when node_modules is missing, then npm exec -- expo prebuild --platform ios. This executes the repository's package scripts and may download dependencies."
    confirmation.addButton(withTitle: "Prepare iOS Project")
    confirmation.addButton(withTitle: "Cancel")
    guard confirmation.runModal() == .alertFirstButtonReturn else { return }
    guard let npm = npmExecutable() else {
      notice = "npm was not found. Install Node.js, then reopen Operate."
      return
    }
    isBusy = true
    status = "Preparing Expo project"
    timeline.append(
      .init(
        time: Self.now(), title: "Expo iOS preparation approved",
        detail: "Dependency installation and native project generation may run.", state: .active))
    Task {
      do {
        let environment = ["PATH": executableSearchPath()]
        if !FileManager.default.fileExists(atPath: repository.appending(path: "node_modules").path)
        {
          status = "Installing JavaScript dependencies"
          let install = try await runner.run(
            executable: npm, arguments: ["ci"], workingDirectory: repository,
            environment: environment, maximumOutputBytes: 24 * 1_024 * 1_024)
          guard install.succeeded else {
            throw RPCError(
              code: -32094, message: "npm ci failed", data: .string(install.stderr))
          }
          timeline.append(
            .init(
              time: Self.now(), title: "JavaScript dependencies installed",
              detail: "npm ci completed", state: .complete))
        }
        status = "Generating iOS project"
        let prebuild = try await runner.run(
          executable: npm,
          arguments: ["exec", "--", "expo", "prebuild", "--platform", "ios"],
          workingDirectory: repository, environment: environment,
          maximumOutputBytes: 32 * 1_024 * 1_024)
        guard prebuild.succeeded else {
          throw RPCError(
            code: -32095, message: "Expo iOS prebuild failed", data: .string(prebuild.stderr))
        }
        containers = ToolchainDiscovery.projectContainers(in: repository)
        guard let first = containers.first else {
          throw RPCError(
            code: -32095,
            message: "Expo completed without producing an .xcworkspace or .xcodeproj")
        }
        selectedContainer = first
        files = Self.children(of: repository, depth: 0)
        await refreshProjectSelection()
        status = "Expo iOS project ready"
        timeline.append(
          .init(
            time: Self.now(), title: "iOS project generated",
            detail: first.path, state: .complete))
      } catch let error as RPCError {
        status = "Expo setup failed"
        notice = error.data?.stringValue.map { "\(error.message)\n\n\($0)" } ?? error.message
        timeline.append(
          .init(
            time: Self.now(), title: "Expo setup failed", detail: error.message,
            state: .warning))
      } catch {
        status = "Expo setup failed"
        notice = error.localizedDescription
      }
      isBusy = false
    }
  }

  func refreshAdapters() {
    adapters = AdapterManager.detect(managedRoot: adapterRoot)
    if !adapters.contains(where: { $0.id == selectedAdapterID && $0.executable != nil }) {
      selectedAdapterID = adapters.first(where: { $0.executable != nil })?.id ?? ""
    }
  }

  func setupWebDriverAgent() {
    guard let entry = wdaStatus.entry, let destination = selectedDestination,
      let xcodebuild = preflight?.xcodebuildPath, let developer = preflight?.developerDirectory
    else {
      notice = "Select the validated Xcode build and a supported Simulator first."
      return
    }
    let confirmation = NSAlert()
    confirmation.messageText = "Build the pinned WebDriverAgent runner?"
    confirmation.informativeText =
      "The verified source archive will be downloaded, checksum-validated, and built locally for \(destination.name). It will listen on loopback only."
    confirmation.addButton(withTitle: "Build Runner")
    confirmation.addButton(withTitle: "Cancel")
    guard confirmation.runModal() == .alertFirstButtonReturn else { return }
    isBusy = true
    status = "Preparing UI automation"
    Task {
      do {
        _ = try await wdaInstaller.install(
          entry: entry, runtime: destination.runtime, destinationUDID: destination.udid,
          stateRoot: wdaRoot, xcodebuild: URL(fileURLWithPath: xcodebuild),
          developerDirectory: URL(fileURLWithPath: developer))
        refreshWDAStatus()
        status = "UI automation ready"
      } catch {
        notice = error.localizedDescription
        status = "UI automation setup failed"
      }
      isBusy = false
    }
  }

  func selectFile(_ url: URL) {
    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
      return
    }
    selectedFile = url
    source =
      (try? String(contentsOf: url, encoding: .utf8)) ?? "This file cannot be displayed as text."
    section = .code
  }

  func saveFile() {
    guard let selectedFile, let activeWorktree,
      selectedFile.standardizedFileURL.path.hasPrefix(activeWorktree.standardizedFileURL.path + "/")
    else {
      notice = "Create an isolated task before editing."
      return
    }
    do {
      try source.write(to: selectedFile, atomically: true, encoding: .utf8)
      Task {
        if let value = try? await runtime.request(method: "workspace.mutated"),
          case .number(let newGeneration) = value["generation"]
        {
          generation = Int(newGeneration)
        } else {
          generation += 1
        }
        status = "Evidence stale"
        timeline.append(
          .init(
            time: Self.now(), title: "Saved \(selectedFile.lastPathComponent)",
            detail: "Mutation generation advanced to \(generation).", state: .complete))
        await refreshEvidence()
      }
    } catch { notice = error.localizedDescription }
  }

  func startTask() {
    guard let repository, isGitRepository,
      !taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      activeWorktree == nil
    else { return }
    let prompt = taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    taskPrompt = ""
    taskTitle = prompt
    generation = 0
    status = "Preparing task"
    isBusy = true
    plan = [
      .init(title: "Create isolated worktree", state: .active),
      .init(title: "Connect task runtime", state: .waiting),
      .init(title: "Connect selected ACP agent", state: .waiting),
      .init(title: "Build and collect fresh evidence", state: .waiting),
      .init(title: "Review and apply selected changes", state: .waiting),
    ]
    timeline.append(
      .init(time: Self.now(), title: "Task requested", detail: prompt, state: .complete))
    Task {
      do {
        let prepared = try await workspaceManager.createTask(
          repository: repository, taskRoot: taskRoot)
        activeWorktree = prepared.worktree
        baseline = prepared.manifest
        files = Self.children(of: prepared.worktree, depth: 0)
        selectedFile = nil
        source = ""
        plan[0].state = .complete
        plan[1].state = .active
        try await startRuntime(workspace: prepared.worktree)
        plan[1].state = .complete
        timeline.append(
          .init(
            time: Self.now(), title: "Isolated task ready", detail: prepared.worktree.path,
            state: .complete))
        guard
          let adapter = adapters.first(where: {
            $0.id == selectedAdapterID && $0.executable != nil
          })
        else {
          plan[2].state = .blocked
          status = "Runtime ready · choose an ACP agent"
          throw RPCError(
            code: -32090,
            message: "Choose an ACP-ready coding agent in Settings before starting a task.")
        }
        plan[2].state = .active
        try await connectAgent(adapter: adapter, workspace: prepared.worktree, prompt: prompt)
        plan[2].state = .complete
        status = "Agent finished · review evidence"
        try await refreshProposedChanges()
        await refreshEvidence()
      } catch {
        if activeWorktree == nil { status = "Task failed" } else { status = "Task needs attention" }
        notice = error.localizedDescription
        if plan.indices.contains(2), plan[2].state == .active { plan[2].state = .blocked }
        if activeWorktree == nil, plan.indices.contains(0) { plan[0].state = .blocked }
        timeline.append(
          .init(
            time: Self.now(), title: "Task preparation failed",
            detail: error.localizedDescription, state: .warning))
      }
      isBusy = false
    }
  }

  func sendAgentPrompt() {
    guard canSendAgentPrompt else { return }
    if activeWorktree == nil {
      startTask()
      return
    }
    guard let client = activeACPClient, let sessionID = activeACPSessionID else { return }
    let prompt = taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    taskPrompt = ""
    isBusy = true
    status = "Agent working"
    timeline.append(
      .init(time: Self.now(), title: "You", detail: prompt, state: .complete))
    Task {
      do {
        let result = try await client.request(
          method: "session/prompt",
          params: try jsonValue(ACPPrompt(sessionID: sessionID, text: prompt)))
        let reason = result.result?["stopReason"]?.stringValue ?? "completed"
        timeline.append(
          .init(
            time: Self.now(), title: "Agent turn finished", detail: "Stop reason: \(reason)",
            state: reason == "end_turn" || reason == "completed" ? .complete : .warning))
        try await refreshProposedChanges()
        await refreshEvidence()
        status = "Agent finished · review evidence"
      } catch {
        status = "Agent needs attention"
        notice = error.localizedDescription
        timeline.append(
          .init(
            time: Self.now(), title: "Agent turn failed", detail: error.localizedDescription,
            state: .warning))
      }
      isBusy = false
    }
  }

  func build() {
    guard canBuild else {
      notice = preflight?.issues.joined(separator: "\n") ?? "Choose a scheme and simulator first."
      return
    }
    Task { _ = await executeBuild() }
  }

  func run() {
    guard canRun else {
      notice = "Choose a buildable scheme and simulator first."
      return
    }
    guard approveRequiredExpoCompatibilityRepair() else { return }
    isBusy = true
    appOperation = isExpoRepository && startDevServerOnRun ? .preparing : .building
    Task {
      do {
        if isExpoRepository && startDevServerOnRun { try await ensureMetro() }
      } catch {
        isBusy = false
        appOperation = .idle
        status = "Metro failed"
        notice = error.localizedDescription
        timeline.append(
          .init(
            time: Self.now(), title: "Metro failed to start",
            detail: error.localizedDescription, state: .warning))
        return
      }
      isBusy = false
      guard await executeBuild(continuingToLaunch: true) else { return }
      await installAndLaunch()
    }
  }

  func refreshApp() {
    guard let destination = selectedDestination, let target = selectedTarget,
      let productPath = target.productPath
    else {
      if canRun { run() } else { notice = "Build and run the app once before refreshing it." }
      return
    }
    guard !isBusy else { return }
    isBusy = true
    appOperation = .refreshing
    status = "Refreshing app"
    Task {
      do {
        if isExpoRepository && startDevServerOnRun { try await ensureMetro() }
        try await ensureRuntime()
        _ = try? await runtime.request(
          method: "app.terminate",
          params: .object([
            "udid": .string(destination.udid), "bundleID": .string(target.bundleID),
          ]))
        _ = try await runtime.request(
          method: "app.install_launch",
          params: .object([
            "udid": .string(destination.udid), "appPath": .string(productPath.path),
            "bundleID": .string(target.bundleID),
          ]))
        await captureScreenshot()
        await refreshEvidence()
        status = "Running"
        timeline.append(
          .init(
            time: Self.now(), title: "Application refreshed",
            detail: "\(target.bundleID) on \(destination.name)", state: .complete))
      } catch {
        status = "Refresh failed"
        notice = error.localizedDescription
        timeline.append(
          .init(
            time: Self.now(), title: "Refresh failed", detail: error.localizedDescription,
            state: .warning))
      }
      appOperation = .idle
      isBusy = false
    }
  }

  func stop() {
    Task {
      if let sessionID = activeACPSessionID {
        try? activeACPClient?.notify(
          method: "session/cancel",
          params: .object(["sessionId": .string(sessionID)]))
      }
      resolveAgentPermission(optionID: nil)
      _ = try? await runtime.request(method: "build.cancel")
      await stopOwnedMetro()
      status = "Cancelled"
      isBusy = false
      appOperation = .idle
      timeline.append(
        .init(
          time: Self.now(), title: "Operation cancelled",
          detail: "Child processes were interrupted.", state: .warning))
    }
  }

  func updateAppearance(_ appearance: SimulatorAppearance) {
    selectedAppearance = appearance
    guard let destination = selectedDestination else { return }
    Task {
      do {
        _ = try await runtime.request(
          method: "simulator.configure",
          params: .object([
            "udid": .string(destination.udid), "appearance": .string(appearance.rawValue),
          ]))
        timeline.append(
          .init(
            time: Self.now(), title: "Appearance set to \(appearance.rawValue)",
            detail: destination.name, state: .complete))
        await captureScreenshot()
      } catch { notice = error.localizedDescription }
    }
  }

  func captureHierarchy() {
    guard isSemanticAutomationReady, let destination = selectedDestination,
      let target = selectedTarget
    else {
      notice = "Run the app on the promoted Simulator tuple before inspecting its UI."
      return
    }
    status = "Inspecting UI"
    Task {
      do {
        try await ensureRuntime()
        let result = try await runtime.request(
          method: "ui.snapshot",
          params: .object([
            "udid": .string(destination.udid), "bundleID": .string(target.bundleID),
          ]))
        guard let values = result["elements"] else {
          throw RPCError(code: -32077, message: "WebDriverAgent returned no hierarchy")
        }
        let data = try JSONEncoder().encode(values)
        hierarchyElements = try JSONDecoder().decode([UIElement].self, from: data)
        if selectedElement == nil
          || !hierarchyElements.contains(where: { $0.childPath == selectedElement?.childPath })
        {
          selectedElement = meaningfulHierarchyElements.first(where: {
            $0.hittable && deterministicSelector(for: $0) != nil
          })
        }
        status = "UI hierarchy ready"
        timeline.append(
          .init(
            time: Self.now(), title: "UI hierarchy captured",
            detail: "\(hierarchyElements.count) structured accessibility elements", state: .complete
          ))
      } catch {
        notice = error.localizedDescription
        status = "UI inspection failed"
      }
    }
  }

  func tapSelectedElement() {
    guard let destination = selectedDestination, let target = selectedTarget,
      let element = selectedElement, let selector = deterministicSelector(for: element)
    else {
      notice = "Select an element with an accessibility identifier or unique label first."
      return
    }
    status = "Performing UI action"
    Task {
      do {
        _ = try await runtime.request(
          method: "ui.perform",
          params: .object([
            "udid": .string(destination.udid), "bundleID": .string(target.bundleID),
            "selector": selector,
            "action": .string("tap"),
          ]))
        status = "UI action passed"
        captureHierarchy()
        await captureScreenshot()
        await refreshEvidence()
      } catch {
        notice = error.localizedDescription
        status = "UI action failed"
      }
    }
  }

  func tapPreview(normalizedX: Double, normalizedY: Double) {
    guard let destination = selectedDestination, let target = selectedTarget else {
      notice = "Build and run the app before interacting with its preview."
      return
    }
    guard wdaStatus.availability == .ready else {
      if wdaStatus.availability == .setupRequired {
        setupWebDriverAgent()
      } else {
        notice = wdaStatus.detail
      }
      return
    }
    guard !isBusy else { return }
    status = "Sending preview tap"
    Task {
      do {
        try await ensureRuntime()
        _ = try await runtime.request(
          method: "ui.perform",
          params: .object([
            "udid": .string(destination.udid), "bundleID": .string(target.bundleID),
            "selector": .object([
              "coordinate": .object([
                "x": .number(normalizedX), "y": .number(normalizedY),
              ])
            ]),
            "action": .string("tap"),
          ]))
        status = "Preview tap sent"
        try await Task.sleep(for: .milliseconds(250))
        await captureScreenshot()
        await refreshEvidence()
      } catch {
        status = "Preview tap failed"
        notice = error.localizedDescription
      }
    }
  }

  func assertSelectedElement() {
    guard let destination = selectedDestination, let target = selectedTarget,
      let element = selectedElement, let selector = deterministicSelector(for: element)
    else {
      notice = "Select an element with an accessibility identifier or unique label first."
      return
    }
    status = "Checking UI assertion"
    Task {
      do {
        let result = try await runtime.request(
          method: "ui.assert",
          params: .object([
            "udid": .string(destination.udid), "bundleID": .string(target.bundleID),
            "criterionID": .string("manual-inspector"),
            "selector": selector,
          ]))
        status = result["passed"]?.boolValue == true ? "UI assertion passed" : "UI assertion failed"
        await refreshEvidence()
      } catch {
        notice = error.localizedDescription
        status = "UI assertion failed"
      }
    }
  }

  func captureCurrentScreenshot() {
    Task { await captureScreenshot() }
  }

  private func deterministicSelector(for element: UIElement) -> JSONValue? {
    if let identifier = element.identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
      !identifier.isEmpty
    {
      return .object(["identifier": .string(identifier)])
    }
    if let label = element.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
      let matches = meaningfulHierarchyElements.filter {
        $0.label == label && $0.type == element.type
      }
      guard matches.count == 1 else { return nil }
      return .object(["label": .string(label), "type": .string(element.type)])
    }
    return nil
  }

  func reviewChanges() {
    guard let activeWorktree, let baseline else { return }
    Task {
      do {
        proposedChanges = try await workspaceManager.proposedChanges(
          worktree: activeWorktree, baseline: baseline)
        status = "Review"
        if plan.indices.contains(4) { plan[4].state = .active }
      } catch { notice = error.localizedDescription }
    }
  }

  func applyAll() {
    guard let activeWorktree, let repository, let baseline else { return }
    Task {
      do {
        let report = try await workspaceManager.apply(
          paths: proposedChanges.map(\.path), from: activeWorktree, to: repository,
          baseline: baseline)
        applyConflicts = report.conflicts
        status = report.conflicts.isEmpty ? "Applied" : "Resolve apply conflicts"
        if report.conflicts.isEmpty, plan.indices.contains(4) { plan[4].state = .complete }
        timeline.append(
          .init(
            time: Self.now(), title: "Apply checked",
            detail: "\(report.applied.count) applied · \(report.conflicts.count) require review",
            state: report.conflicts.isEmpty ? .complete : .warning))
      } catch { notice = error.localizedDescription }
    }
  }

  func discardTask() {
    guard let activeWorktree, let repository else { return }
    Task {
      do {
        await stopOwnedMetro()
        activeACPClient?.cancel()
        activeACPClient = nil
        activeACPSessionID = nil
        resolveAgentPermission(optionID: nil)
        await runtime.stop()
        try await workspaceManager.discard(
          worktree: activeWorktree, repository: repository, taskRoot: taskRoot)
        self.activeWorktree = nil
        baseline = nil
        files = Self.children(of: repository, depth: 0)
        proposedChanges = []
        applyConflicts = []
        evidence = []
        verificationReport = nil
        taskTitle = ""
        plan = []
        status = "Ready"
      } catch { notice = error.localizedDescription }
    }
  }

  func resume(_ recovered: RecoverableWorkspace) {
    let original = URL(fileURLWithPath: recovered.manifest.repositoryRoot)
    repository = original
    activeWorktree = recovered.worktree
    baseline = recovered.manifest
    isGitRepository = true
    containers = ToolchainDiscovery.projectContainers(in: original)
    selectedContainer = containers.first
    files = Self.children(of: recovered.worktree, depth: 0)
    taskTitle = "Recovered task"
    status = "Recovering"
    timeline = [
      .init(
        time: Self.now(), title: "Recovered isolated task",
        detail: recovered.worktree.path, state: .complete)
    ]
    plan = [
      .init(title: "Review recovered edits", state: .active),
      .init(title: "Build and collect fresh evidence", state: .waiting),
      .init(title: "Apply or discard", state: .waiting),
    ]
    Task {
      do {
        try await startRuntime(workspace: recovered.worktree)
        await loadRepository()
        try await refreshProposedChanges()
        recoverableWorkspaces.removeAll { $0.id == recovered.id }
        status = "Recovered · review required"
      } catch {
        notice = error.localizedDescription
        status = "Recovery blocked"
      }
    }
  }

  func openSimulator() {
    guard
      let app = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.iphonesimulator")
    else {
      notice = "Simulator.app is unavailable. Select a full Xcode installation first."
      return
    }
    NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, error in
      if let error { Task { @MainActor in self.notice = error.localizedDescription } }
    }
  }

  func exportDiagnostics() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "iosdev-diagnostics.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let redactor = SecretRedactor(repositoryRoots: [repository].compactMap { $0 })
      let payload: [String: JSONValue] = [
        "generatedAt": .string(ISO8601DateFormatter().string(from: Date())),
        "status": .string(status),
        "toolchain": .string(redactor.redact(preflight?.issues.joined(separator: "\n") ?? "")),
        "events": .array(
          timeline.map {
            .object([
              "time": .string($0.time), "title": .string($0.title),
              "detail": .string(redactor.redact($0.detail)),
            ])
          }),
        "evidence": (try? jsonValue(evidence)) ?? .array([]),
      ]
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(payload).write(to: url, options: .atomic)
    } catch { notice = error.localizedDescription }
  }

  public func loadDesignPreview() {
    designPreview = true
    repository = URL(fileURLWithPath: "/Synthetic/TravelApp")
    activeWorktree = URL(fileURLWithPath: "/Synthetic/Tasks/profile-dark-mode")
    isGitRepository = true
    branchName = "main"
    status = "Verifying"
    isBusy = true
    generation = 2
    taskTitle =
      "Add dark mode support to the Profile screen and verify it on small and large iPhones."
    selectedScheme = "TravelApp"
    selectedDestinationID = "SYNTHETIC-IPHONE"
    destinations = [
      .init(
        udid: "SYNTHETIC-IPHONE", name: "iPhone 16 Pro", deviceType: "iPhone 16 Pro",
        runtime: "iOS 18.2", state: "Booted")
    ]
    plan = [
      .init(title: "Review Profile implementation", state: .complete),
      .init(title: "Update colors and assets", state: .complete),
      .init(title: "Build and run on small phone", state: .complete),
      .init(title: "Verify dark mode appearance", state: .active),
      .init(title: "Run on large phone", state: .waiting),
    ]
    timeline = [
      .init(
        time: "10:42", title: "Read ProfileView.swift", detail: "Synthetic fixture",
        state: .complete),
      .init(
        time: "10:44", title: "Build succeeded", detail: "Synthetic fixture · 24s", state: .complete
      ),
      .init(
        time: "10:46", title: "Application launched", detail: "Synthetic fixture", state: .complete),
      .init(time: "10:47", title: "Verifying Profile", detail: "Synthetic fixture", state: .active),
    ]
    evidence = [
      .init(
        kind: .build, status: .passed, taskGeneration: 2,
        diagnosticSummary: "Synthetic fixture · build succeeded in 24s"),
      .init(
        kind: .launch, status: .passed, taskGeneration: 2,
        diagnosticSummary: "Synthetic fixture · app launched"),
      .init(
        kind: .uiAssertion, status: .passed, taskGeneration: 2, criterionID: "profile-dark",
        diagnosticSummary: "Synthetic fixture · 5 assertions passed"),
      .init(
        kind: .screenshot, status: .informational, taskGeneration: 2,
        diagnosticSummary: "Synthetic fixture · comparing screenshots"),
      .init(
        kind: .runtimeLog, status: .passed, taskGeneration: 2,
        diagnosticSummary: "Synthetic fixture · no unacknowledged errors"),
    ]
    verificationReport = .init(
      status: .partiallyVerified, currentEvidence: evidence, staleEvidence: [],
      missing: ["Fresh screenshot"])
    proposedChanges = [
      .init(path: "ProfileView.swift", kind: .modified, binary: false),
      .init(path: "ProfileColors.swift", kind: .modified, binary: false),
      .init(path: "Assets.xcassets", kind: .modified, binary: true),
      .init(path: "ProfileTests.swift", kind: .added, binary: false),
    ]
  }

  public func loadDesignFailurePreview() {
    loadDesignPreview()
    isBusy = false
    status = "Build failed"
    generation = 3
    timeline.append(
      .init(
        time: "10:49", title: "Build failed", detail: "Synthetic fixture · compiler error",
        state: .warning))
    let failed = Evidence(
      kind: .build, status: .failed, taskGeneration: 3,
      diagnosticSummary: "Synthetic fixture · ProfileColors.swift:42")
    evidence.append(failed)
    verificationReport = .init(
      status: .failed, currentEvidence: [failed], staleEvidence: Array(evidence.dropLast()),
      missing: ["Fresh successful build", "Launch and UI evidence are stale"])
  }

  public func loadDesignBuildPreview() {
    loadDesignPreview()
    currentScreenshot = nil
    appOperation = .building
    isBusy = true
    status = "Building"
    timeline.append(
      .init(
        time: "10:49", title: "Build started", detail: "TravelApp · iPhone 16 Pro",
        state: .active))
  }

  public func loadSettingsPreview() {
    section = .settings
    preflight = .init(
      developerDirectory: "/Applications/Xcode.app/Contents/Developer",
      xcodebuildPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild",
      simctlPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl",
      xcodeVersion: "26.6", xcodeBuild: "17F113", isFullXcode: true, issues: [])
    destinations = [
      .init(
        udid: "D8368E82-B87A-459C-ADE0-473ABC9CFD54", name: "iPhone 17 Pro",
        deviceType: "iPhone 17 Pro", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        state: "Booted")
    ]
    selectedDestinationID = destinations[0].udid
    refreshAdapters()
    refreshWDAStatus()
  }

  private func loadRepository() async {
    guard let repository else { return }
    let git = URL(fileURLWithPath: "/usr/bin/git")
    if let inside = try? await runner.run(
      executable: git, arguments: ["-C", repository.path, "rev-parse", "--is-inside-work-tree"])
    {
      isGitRepository = inside.succeeded
    }
    if isGitRepository,
      let branch = try? await runner.run(
        executable: git, arguments: ["-C", repository.path, "branch", "--show-current"])
    {
      let value = branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      branchName = value.isEmpty ? "detached" : value
    } else {
      branchName = "read-only"
    }
    await refreshProjectSelection()
    status =
      !isGitRepository ? "Browse only" : needsExpoPreparation ? "Expo setup required" : "Ready"
  }

  private func refreshToolchain() async {
    preflight = await ToolchainDiscovery.preflight(developerDirectory: developerDirectory)
    if let selected = preflight?.developerDirectory {
      developerDirectory = URL(fileURLWithPath: selected)
    }
    refreshAdapters()
    await refreshDestinations()
    if repository != nil { await refreshProjectSelection() }
  }

  private func refreshProjectSelection() async {
    guard let container = selectedContainer, let preflight,
      let xcodebuild = preflight.xcodebuildPath, let developer = preflight.developerDirectory
    else {
      schemes = []
      selectedScheme = ""
      return
    }
    do {
      let listing = try await ToolchainDiscovery.listProject(
        container: container, xcodebuild: URL(fileURLWithPath: xcodebuild),
        developerDirectory: URL(fileURLWithPath: developer))
      var discoveredSchemes = listing.schemes
      if container.pathExtension == "xcworkspace" {
        let workspaceDirectory = container.deletingLastPathComponent().standardizedFileURL.path
        let localProjects = containers.prefix(16).filter {
          $0.pathExtension == "xcodeproj"
            && $0.standardizedFileURL.path.hasPrefix(workspaceDirectory + "/")
        }
        var localSchemes: Set<String> = []
        for project in localProjects {
          if let projectListing = try? await ToolchainDiscovery.listProject(
            container: project, xcodebuild: URL(fileURLWithPath: xcodebuild),
            developerDirectory: URL(fileURLWithPath: developer))
          {
            localSchemes.formUnion(projectListing.schemes)
          }
        }
        let applicationSchemes = listing.schemes.filter(localSchemes.contains)
        if !applicationSchemes.isEmpty { discoveredSchemes = applicationSchemes }
      }
      schemes = ToolchainDiscovery.prioritizeSchemes(discoveredSchemes, for: container)
      if !schemes.contains(selectedScheme) { selectedScheme = schemes.first ?? "" }
    } catch {
      notice = error.localizedDescription
      schemes = []
    }
  }

  private func refreshDestinations() async {
    guard let preflight, let simctl = preflight.simctlPath,
      let developer = preflight.developerDirectory
    else {
      destinations = []
      selectedDestinationID = ""
      refreshWDAStatus()
      return
    }
    do {
      destinations = try await ToolchainDiscovery.simulators(
        simctl: URL(fileURLWithPath: simctl),
        developerDirectory: URL(fileURLWithPath: developer))
      if !destinations.contains(where: { $0.udid == selectedDestinationID }) {
        selectedDestinationID = destinations.first?.udid ?? ""
      }
    } catch {
      destinations = []
      selectedDestinationID = ""
      notice = "Simulator discovery failed: \(error.localizedDescription)"
    }
    refreshWDAStatus()
  }

  private func refreshWDAStatus() {
    wdaStatus = WDACompatibilityGate.status(
      preflight: preflight, runtime: selectedDestination?.runtime, stateRoot: wdaRoot)
  }

  private func connectAgent(
    adapter: DetectedAdapter, workspace: URL, prompt: String
  ) async throws {
    guard let executable = adapter.executable else {
      throw RPCError(code: -32090, message: "The selected ACP adapter is unavailable")
    }
    let workspaceHandler = ACPWorkspaceRequestHandler(
      workspace: workspace, allowWrites: true,
      didMutate: { [weak self] in await self?.recordAgentMutation() })
    let client = try ACPClient(
      executable: executable, arguments: adapter.launchArguments, workspace: workspace,
      onUpdate: { [weak self] update in
        Task { @MainActor in self?.consumeAgentUpdate(update) }
      },
      onRequest: { [weak self] request in
        if request.method == "fs/read_text_file" || request.method == "fs/write_text_file" {
          return await workspaceHandler.handle(request)
        }
        if request.method == "session/request_permission", let self {
          return await self.presentAgentPermission(request)
        }
        return .init(
          id: request.id,
          error: .init(code: -32601, message: "Unsupported ACP client method"))
      },
      onDiagnostic: { [weak self] diagnostic in
        let text = diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { @MainActor in
          self?.timeline.append(
            .init(time: Self.now(), title: "Agent diagnostic", detail: text, state: .warning))
        }
      })
    activeACPClient?.cancel()
    activeACPClient = client

    let initialized = try await client.request(
      method: "initialize",
      params: try jsonValue(ACPInitialize(clientVersion: "0.1.0", allowWrites: true)))
    guard initialized.result?["protocolVersion"]?.numberValue == Double(ACPProtocol.version) else {
      client.cancel()
      activeACPClient = nil
      throw RPCError(code: -32091, message: "The selected agent did not negotiate ACP v1")
    }
    let mcp = ACPMCPServer(
      name: "iOS Development Runtime", command: try mcpExecutable().path,
      env: try await runtime.mcpEnvironment())
    let session = try await client.request(
      method: "session/new", params: try jsonValue(ACPNewSession(cwd: workspace, mcpServers: [mcp]))
    )
    guard let sessionID = session.result?["sessionId"]?.stringValue else {
      throw RPCError(code: -32092, message: "The ACP agent did not return a session ID")
    }
    activeACPSessionID = sessionID
    status = "Agent working"
    timeline.append(
      .init(
        time: Self.now(), title: "(adapter.displayName) connected",
        detail: "ACP v1 session (sessionID)", state: .complete))

    let context = """
      \(prompt)

      You are editing an isolated task worktree at \(workspace.path). Use the iOS Development Runtime MCP tools for builds, Simulator operations, UI automation, and verification. The selected scheme is \(selectedScheme.isEmpty ? "not selected" : selectedScheme), and the selected Simulator is \(selectedDestination?.name ?? "not selected"). Expo development-server startup is currently \(startDevServerOnRun ? "enabled" : "disabled") by the user. For Expo or React Native development-client apps, call devserver.start before app.install_launch (or pass startDevServer=true) when it is enabled. Do not claim completion from prose: submit only fresh machine-recorded evidence from the current mutation generation. Reviewable changes must remain inside this worktree.
      """
    let result = try await client.request(
      method: "session/prompt",
      params: try jsonValue(ACPPrompt(sessionID: sessionID, text: context)))
    let reason = result.result?["stopReason"]?.stringValue ?? "completed"
    timeline.append(
      .init(
        time: Self.now(), title: "Agent turn finished", detail: "Stop reason: \(reason)",
        state: reason == "end_turn" || reason == "completed" ? .complete : .warning))
  }

  private func recordAgentMutation() async {
    if let value = try? await runtime.request(method: "workspace.mutated"),
      case .number(let newGeneration) = value["generation"]
    {
      generation = Int(newGeneration)
    } else {
      generation += 1
    }
    status = "Agent working · evidence stale"
  }

  private func consumeAgentUpdate(_ envelope: RPCEnvelope) {
    guard envelope.method == "session/update", let update = envelope.params?["update"] else {
      return
    }
    let kind = update["sessionUpdate"]?.stringValue ?? "update"
    switch kind {
    case "agent_message_chunk":
      guard let text = update["content"]?["text"]?.stringValue, !text.isEmpty else { return }
      timeline.append(.init(time: Self.now(), title: "Agent", detail: text, state: .active))
    case "tool_call", "tool_call_update":
      let title = update["title"]?.stringValue ?? update["name"]?.stringValue ?? "Tool call"
      let state = update["status"]?.stringValue == "failed" ? TimelineItem.State.warning : .active
      timeline.append(
        .init(
          time: Self.now(), title: title,
          detail: update["status"]?.stringValue ?? "In progress", state: state))
    case "plan":
      timeline.append(
        .init(
          time: Self.now(), title: "Agent plan updated", detail: "Structured ACP plan received",
          state: .active))
    default: break
    }
  }

  private func presentAgentPermission(_ request: RPCEnvelope) async -> RPCEnvelope {
    let values = request.params?["options"]?.arrayValue ?? []
    let options = values.compactMap { value -> AgentPermissionOption? in
      guard let id = value["optionId"]?.stringValue, let name = value["name"]?.stringValue else {
        return nil
      }
      return .init(id: id, name: name, kind: value["kind"]?.stringValue ?? "allow_once")
    }
    let title = request.params?["toolCall"]?["title"]?.stringValue ?? "Agent permission"
    let detail =
      request.params?["toolCall"]?["name"]?.stringValue
      ?? "Review this operation before allowing it."
    return await withCheckedContinuation { continuation in
      permissionContinuation = continuation
      pendingPermissionRPCID = request.id
      pendingAgentPermission = .init(title: title, detail: detail, options: options)
      status = "Awaiting permission"
    }
  }

  func resolveAgentPermission(optionID: String?) {
    guard let continuation = permissionContinuation else {
      pendingAgentPermission = nil
      return
    }
    permissionContinuation = nil
    let requestID = pendingPermissionRPCID
    pendingPermissionRPCID = nil
    pendingAgentPermission = nil
    status = "Agent working"
    let outcome: JSONValue =
      optionID.map {
        .object(["outcome": .string("selected"), "optionId": .string($0)])
      } ?? .object(["outcome": .string("cancelled")])
    continuation.resume(returning: .init(id: requestID, result: .object(["outcome": outcome])))
  }

  private func startRuntime(workspace: URL) async throws {
    try await runtime.start(
      executable: try runtimeExecutable(), workspace: workspace, stateRoot: runtimeRoot,
      developerDirectory: developerDirectory)
  }

  private func ensureRuntime() async throws {
    guard let workspace = taskWorkspace else { throw RuntimeControllerError.notRunning }
    do {
      _ = try await runtime.request(method: "workspace.describe")
    } catch {
      try await startRuntime(workspace: workspace)
    }
  }

  private func executeBuild(continuingToLaunch: Bool = false) async -> Bool {
    guard let container = taskContainer(), let destination = selectedDestination else {
      return false
    }
    isBusy = true
    appOperation = .building
    status = "Building"
    timeline.append(
      .init(
        time: Self.now(), title: "Build started",
        detail: "\(selectedScheme) · \(destination.name)", state: .active))
    do {
      try await ensureRuntime()
      let result = try await runtime.request(
        method: "build.run",
        params: .object([
          "container": .string(container.path), "scheme": .string(selectedScheme),
          "configuration": .string("Debug"),
          "destination": .string("platform=iOS Simulator,id=\(destination.udid)"),
        ]))
      let passed = result["succeeded"]?.boolValue == true
      status = passed ? "Build succeeded" : "Build failed"
      timeline.append(
        .init(
          time: Self.now(), title: status,
          detail: passed
            ? "Fresh build evidence recorded." : (result["log"]?.stringValue ?? "See build log."),
          state: passed ? .complete : .warning))
      if plan.indices.contains(3) { plan[3].state = passed ? .active : .blocked }
      await refreshEvidence()
      isBusy = false
      if !passed || !continuingToLaunch { appOperation = .idle }
      return passed
    } catch {
      isBusy = false
      appOperation = .idle
      status = "Build blocked"
      notice = error.localizedDescription
      timeline.append(
        .init(
          time: Self.now(), title: "Build blocked", detail: error.localizedDescription,
          state: .warning))
      return false
    }
  }

  private func installAndLaunch() async {
    guard let container = taskContainer(), let destination = selectedDestination else { return }
    isBusy = true
    appOperation = .launching
    status = "Preparing launch"
    do {
      _ = try await runtime.request(
        method: "simulator.boot", params: .object(["udid": .string(destination.udid)]))
      let targets: [AppTarget] = try await runtime.request(
        [AppTarget].self, method: "target.discover",
        params: .object([
          "container": .string(container.path), "scheme": .string(selectedScheme),
          "configuration": .string("Debug"),
          "destination": .string("platform=iOS Simulator,id=\(destination.udid)"),
        ]))
      guard let target = targets.first, let productPath = target.productPath else {
        throw RPCError(
          code: -32056,
          message:
            "The \(selectedScheme) scheme does not produce a runnable iOS app. Choose the application scheme from the App menu and try Run again."
        )
      }
      selectedTarget = target
      _ = try await runtime.request(
        method: "app.install_launch",
        params: .object([
          "udid": .string(destination.udid), "appPath": .string(productPath.path),
          "bundleID": .string(target.bundleID),
        ]))
      status = "Running"
      timeline.append(
        .init(
          time: Self.now(), title: "Application launched",
          detail: "\(target.bundleID) on \(destination.name)", state: .complete))
      await captureScreenshot()
      await refreshEvidence()
    } catch {
      status = "Launch failed"
      notice = error.localizedDescription
      timeline.append(
        .init(
          time: Self.now(), title: "Launch failed", detail: error.localizedDescription,
          state: .warning))
    }
    appOperation = .idle
    isBusy = false
  }

  private func captureScreenshot() async {
    guard let destination = selectedDestination else { return }
    do {
      _ = try await runtime.request(
        method: "screenshot.capture", params: .object(["udid": .string(destination.udid)]))
      await refreshEvidence()
    } catch { notice = error.localizedDescription }
  }

  private func refreshEvidence() async {
    do {
      evidence = try await runtime.request([Evidence].self, method: "evidence.list")
      currentScreenshot = evidence.reversed().first(where: { $0.kind == .screenshot }).flatMap {
        $0.artifactPaths.first.map(URL.init(fileURLWithPath:))
      }
      verificationReport = try await runtime.request(
        VerificationReport.self, method: "verification.status",
        params: .object([
          "codeChanged": .bool(activeWorktree != nil), "uiChanged": .bool(requiresUIVerification),
          "testsChanged": .bool(false),
        ]))
    } catch {
      verificationReport = nil
    }
  }

  private func refreshRecovery() async {
    recoverableWorkspaces = (try? await workspaceManager.recoverableTasks(taskRoot: taskRoot)) ?? []
  }

  private func refreshProposedChanges() async throws {
    guard let activeWorktree, let baseline else { return }
    proposedChanges = try await workspaceManager.proposedChanges(
      worktree: activeWorktree, baseline: baseline)
  }

  private func taskContainer() -> URL? {
    guard let selectedContainer, let repository, let workspace = taskWorkspace else { return nil }
    let root = repository.standardizedFileURL.path
    let path = selectedContainer.standardizedFileURL.path
    guard path == root || path.hasPrefix(root + "/") else { return selectedContainer }
    let relative = String(path.dropFirst(root.count)).trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))
    return relative.isEmpty ? workspace : workspace.appending(path: relative)
  }

  private func runtimeExecutable() throws -> URL {
    let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
    let candidates = [
      executableDirectory?.appending(path: "iosdevd"),
      Bundle.main.resourceURL?.appending(path: "bin/iosdevd"),
    ].compactMap { $0 }
    if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) {
      return match
    }
    throw RuntimeControllerError.executableMissing(candidates.first?.path ?? "iosdevd")
  }

  private func mcpExecutable() throws -> URL {
    let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
    let candidates = [
      executableDirectory?.appending(path: "iosdev-mcp"),
      Bundle.main.resourceURL?.appending(path: "bin/iosdev-mcp"),
    ].compactMap { $0 }
    if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) {
      return match
    }
    throw RuntimeControllerError.executableMissing(candidates.first?.path ?? "iosdev-mcp")
  }

  private func npmExecutable() -> URL? {
    ["/opt/homebrew/bin/npm", "/usr/local/bin/npm", "/usr/bin/npm"]
      .map(URL.init(fileURLWithPath:))
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  private func approveRequiredExpoCompatibilityRepair() -> Bool {
    guard isExpoRepository, let container = taskContainer() else { return true }
    let fmtHeader = ExpoCompatibility.fmtHeader(for: container)
    let mmkvSource = ExpoCompatibility.mmkvAESSource(for: container)
    let needsFMT = ExpoCompatibility.needsFMTConstevalRepair(at: fmtHeader)
    let needsMMKV = ExpoCompatibility.needsMMKVSecureWipeRepair(at: mmkvSource)
    guard needsFMT || needsMMKV else { return true }

    let confirmation = NSAlert()
    confirmation.messageText = "Apply the Expo compatibility repairs?"
    confirmation.informativeText =
      "This project includes generated fmt or MMKV sources that Apple Clang 21 cannot compile. Operate will apply narrow repairs inside ios/Pods only. Regenerating ios/Pods removes them."
    confirmation.addButton(withTitle: "Apply and Run")
    confirmation.addButton(withTitle: "Cancel")
    guard confirmation.runModal() == .alertFirstButtonReturn else { return false }
    do {
      if needsFMT { try ExpoCompatibility.applyFMTConstevalRepair(at: fmtHeader) }
      if needsMMKV { try ExpoCompatibility.applyMMKVSecureWipeRepair(at: mmkvSource) }
      timeline.append(
        .init(
          time: Self.now(), title: "Expo compatibility repairs applied",
          detail: "Patched generated dependencies for Apple Clang 21.", state: .complete))
      return true
    } catch {
      notice = error.localizedDescription
      return false
    }
  }

  private func ensureMetro() async throws {
    guard let workspace = taskWorkspace, let npm = npmExecutable() else {
      throw RPCError(
        code: -32096,
        message: "npm was not found. Install Node.js, then reopen Operate.")
    }

    if metroTask != nil, metroWorkspace?.standardizedFileURL != workspace.standardizedFileURL {
      await stopOwnedMetro()
    }
    if await isMetroReady() {
      timeline.append(
        .init(
          time: Self.now(), title: "Metro ready",
          detail: metroTask == nil ? "Using the existing server on port 8081." : workspace.path,
          state: .complete))
      return
    }

    if metroTask == nil {
      status = "Starting Metro"
      metroExitDiagnostic = nil
      metroWorkspace = workspace
      let runID = UUID()
      metroRunID = runID
      let task = Task {
        try await runner.run(
          executable: npm, arguments: ["start"], workingDirectory: workspace,
          environment: [
            "PATH": executableSearchPath(),
            "BROWSER": "none",
            "CI": "1",
          ], maximumOutputBytes: 8 * 1_024 * 1_024)
      }
      metroTask = task
      timeline.append(
        .init(
          time: Self.now(), title: "Starting Metro",
          detail: "Serving the Expo project from \(workspace.path)", state: .active))
      Task { [weak self] in
        let result = await task.result
        guard let self, self.metroRunID == runID else { return }
        switch result {
        case .success(let outcome):
          let detail = outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
          self.metroExitDiagnostic =
            detail.isEmpty
            ? "Metro exited with status \(outcome.terminationStatus)." : detail
        case .failure(let error):
          self.metroExitDiagnostic = error.localizedDescription
        }
      }
    }

    for _ in 0..<120 {
      if await isMetroReady() {
        status = "Metro ready"
        timeline.append(
          .init(
            time: Self.now(), title: "Metro ready", detail: "Listening on port 8081.",
            state: .complete))
        return
      }
      if let metroExitDiagnostic {
        cancelOwnedMetro()
        throw RPCError(
          code: -32097, message: "Metro exited before it was ready",
          data: .string(metroExitDiagnostic))
      }
      try await Task.sleep(for: .milliseconds(250))
    }

    await stopOwnedMetro()
    throw RPCError(
      code: -32098,
      message: "Metro did not become ready on port 8081 within 30 seconds.")
  }

  private func isMetroReady() async -> Bool {
    guard let url = URL(string: "http://127.0.0.1:8081/status") else { return false }
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

  private func cancelOwnedMetro() {
    metroRunID = nil
    metroWorkspace = nil
    metroExitDiagnostic = nil
    metroTask?.cancel()
    metroTask = nil
  }

  private func stopOwnedMetro() async {
    guard let task = metroTask else {
      cancelOwnedMetro()
      return
    }
    cancelOwnedMetro()
    _ = await task.result
  }

  private func executableSearchPath() -> String {
    let standard = [
      "/opt/homebrew/bin", "/usr/local/bin",
      FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
      "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]
    let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
    var seen: Set<String> = []
    return (standard + inherited.split(separator: ":").map(String.init))
      .filter { !$0.isEmpty && seen.insert($0).inserted }
      .joined(separator: ":")
  }

  private static func children(of url: URL, depth: Int) -> [FileNode] {
    guard depth < 4,
      let urls = try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    else { return [] }
    return urls.filter { ![".build", "DerivedData", "Pods"].contains($0.lastPathComponent) }
      .sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
      .map { item in
        let directory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        return FileNode(url: item, children: directory ? children(of: item, depth: depth + 1) : nil)
      }
  }

  private static func now() -> String {
    Date().formatted(date: .omitted, time: .shortened)
  }
}
