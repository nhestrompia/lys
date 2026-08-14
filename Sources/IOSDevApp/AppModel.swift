import AppKit
import IOSDevCore
import SwiftUI

enum PrimarySection: String, CaseIterable, Identifiable {
  case agent = "Develop"
  case code = "Code"
  case git = "Deploy"
  case changes = "Changes"
  case settings = "Settings"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .agent: "hammer"
    case .code: "chevron.left.forwardslash.chevron.right"
    case .git: "paperplane"
    case .changes: "square.and.pencil"
    case .settings: "gearshape"
    }
  }
}

enum EvidenceWorkspaceTab: String, CaseIterable, Identifiable {
  case terminal = "Terminal"
  case logs = "Logs"
  case evidence = "Evidence"

  var id: String { rawValue }
}

struct FileNode: Identifiable, Hashable, Sendable {
  var id: String { url.path }
  var url: URL
  var name: String { url.lastPathComponent }
  var isDirectory: Bool
}

enum FileTreeLoader {
  enum LoadResult: Sendable {
    case success([FileNode])
    case failure(String)
  }

  private static let hiddenGeneratedDirectories = [".build", "DerivedData", "Pods"]

  nonisolated static func loadContents(of directory: URL) -> LoadResult {
    do {
      return .success(try contents(of: directory))
    } catch {
      return .failure(error.localizedDescription)
    }
  }

  nonisolated static func contents(of directory: URL) throws -> [FileNode] {
    let urls = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles])

    return urls.compactMap { item in
      guard !hiddenGeneratedDirectories.contains(item.lastPathComponent) else { return nil }
      let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      // Treat directory symlinks as leaves. Expanding them can recurse outside the repository or
      // cycle back into an ancestor.
      let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true
      return FileNode(url: item, isDirectory: isDirectory)
    }
    .sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}

struct TimelineItem: Identifiable {
  enum State { case complete, active, waiting, warning }
  enum Category { case system, human, agent, tool, permission }
  let id = UUID()
  var time: String
  var title: String
  var detail: String
  var state: State
  var category: Category = .system
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

  var isAllow: Bool { kind.hasPrefix("allow") }
  var isPersistent: Bool { kind.hasSuffix("always") }
  var displayName: String {
    let normalized = name.lowercased()
    switch kind {
    case "allow_once" where normalized == "allow" || normalized.contains("allow once"):
      return "Allow once"
    case "allow_always"
    where normalized.contains("session") || normalized.contains("always")
      || normalized.contains("don't ask") || normalized.contains("dont ask"):
      return "Allow for this task"
    case "reject_once": return "Deny"
    case "reject_always": return "Always deny"
    default: return name
    }
  }
}

struct AgentPermissionRequest: Identifiable {
  let id = UUID()
  var toolCallID: String?
  var title: String
  var detail: String
  var scopeLabel: String
  var scopeDetail: String?
  var command: String?
  var options: [AgentPermissionOption]
}

private struct AgentToolContext {
  var toolCallID: String
  var title: String?
  var name: String?
  var kind: String?
  var status: String?
  var rawInput: JSONValue?
  var rawOutput: JSONValue?
  var locations: [String] = []
}

struct TerminalEntry: Identifiable {
  enum State { case running, succeeded, failed, cancelled }
  let id: UUID
  var command: String
  var workingDirectory: String
  var output: String
  var state: State
  var startedAt: Date

  init(command: String, workingDirectory: String, state: State = .running) {
    id = UUID()
    self.command = command
    self.workingDirectory = workingDirectory
    output = ""
    self.state = state
    startedAt = Date()
  }
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
    case .building: "Waiting for Xcode to finish. The embedded Simulator will update after launch."
    case .launching: "Installing the latest build on the selected Simulator."
    case .refreshing: "Relaunching the installed app and capturing a fresh screenshot."
    }
  }
}

enum PreviewInteractionState: Equatable {
  case unavailable
  case warming
  case ready
  case sending

  var label: String {
    switch self {
    case .unavailable: "Interaction unavailable"
    case .warming: "Connecting interaction…"
    case .ready: "Interactive"
    case .sending: "Updating Simulator…"
    }
  }
}

struct PreviewTapFeedback: Identifiable, Equatable {
  let id = UUID()
  let x: Double
  let y: Double
}

private struct PreviewTapRequest {
  let x: Double
  let y: Double
  let sessionID: UUID
}

private struct PreviewSwipeRequest {
  let startX: Double
  let startY: Double
  let endX: Double
  let endY: Double
  let sessionID: UUID
}

private enum PreviewInteractionRequest {
  case tap(PreviewTapRequest)
  case swipe(PreviewSwipeRequest)

  var sessionID: UUID {
    switch self {
    case .tap(let request): request.sessionID
    case .swipe(let request): request.sessionID
    }
  }
}

struct TaskCompletionSummary: Equatable {
  var title: String
  var done: String
  var worked: String
  var lacking: String
  var passed: Bool
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
  @Published var activeTaskIntent: AgentTaskIntent?
  @Published var activeJourney: JourneyRecord?
  @Published var timeline: [TimelineItem] = []
  @Published var plan: [TaskPlanItem] = []
  @Published var evidence: [Evidence] = []
  @Published var verificationReport: VerificationReport?
  @Published var taskSummary: TaskCompletionSummary?
  @Published var selectedElement: UIElement?
  @Published var hierarchyElements: [UIElement] = []
  @Published var notice: String?
  @Published var proposedChanges: [ProposedChange] = []
  @Published private(set) var proposedChangesRevision = 0
  @Published var repositoryChanges: [ProposedChange] = []
  @Published private(set) var repositoryChangesRevision = 0
  @Published var applyConflicts: [ApplyConflict] = []
  @Published var isBusy = false
  @Published var selectedAppearance: SimulatorAppearance = .light
  @Published var currentScreenshot: URL?
  @Published var currentScreenshotImage: NSImage?
  @Published var previewInteractionState: PreviewInteractionState = .unavailable
  @Published var previewTapFeedback: PreviewTapFeedback?
  @Published var previewLatencyMS: Int?
  @Published var appOperation: AppOperation = .idle
  @Published var adapters: [DetectedAdapter] = []
  @Published var selectedAdapterID = ""
  @Published var agentConfigOptions: [ACPConfigOption] = []
  @Published private(set) var localAgentConfigOptions: [ACPConfigOption] = []
  @Published var wdaStatus = WDAStatus(
    availability: .unsupported, title: "Checking semantic UI automation",
    detail: "Select Xcode and a Simulator destination.", entry: nil, cacheDirectory: nil)
  @Published var recoverableWorkspaces: [RecoverableWorkspace] = []
  @Published var testSecretIDs: [String] = BlueprintSecretStore.accounts()
  @Published var appStoreConnection: AppStoreConnection?
  @Published var appStoreApps: [AppStoreApp] = []
  @Published var appStoreConnectionPhase: AppStoreConnectionPhase = .disconnected
  @Published var appStoreConnectionError: String?
  @Published var appStoreLastSyncedAt: Date?
  @Published var isAppStoreSigningMetadataLoading = false
  @Published var appStoreSigningMetadataMessage: String?
  @Published var appStoreDistributionTarget: AppTarget?
  @Published var appStoreSelectedAppID: String?
  @Published var appStoreVersions: [AppStoreVersion] = []
  @Published var appStoreBuilds: [AppStoreBuild] = []
  @Published var appStoreBuildIcon: AppStoreBuildIcon?
  @Published var appStoreBetaGroups: [AppStoreBetaGroup] = []
  @Published var appStoreTesterUsages: [String: AppStoreTesterUsage] = [:]
  @Published var appStoreTesterUsagePeriod: AppStoreTesterUsagePeriod = .oneYear
  @Published var isAppStoreTesterAnalyticsLoading = false
  var appStoreTesterAnalyticsRequestID = UUID()
  @Published var appStoreLocalizations: [AppStoreVersionLocalization] = []
  @Published var appStoreScreenshotSets: [AppStoreScreenshotSet] = []
  @Published var appStoreFeedback: [AppStoreFeedback] = []
  @Published var appStoreSelectedVersionID: String?
  @Published var appStoreSelectedBuildID: String?
  @Published var appStoreSectionErrors: [AppStoreDataSection: String] = [:]
  @Published var appStoreDeploymentPhase: AppStoreDeploymentPhase = .idle
  @Published var appStoreDeploymentError: String?
  @Published var appStoreDeploymentLastSyncedAt: Date?
  @Published var appStoreSelectionWarning: String?
  @Published var appStoreMutationError: String?
  @Published var isAppStoreMutationInProgress = false
  @Published var appStoreUploadPhase: AppStoreUploadPhase = .idle
  @Published var appStoreUploadPreflight: AppStoreUploadPreflight?
  @Published var appStoreUploadOptions = AppStoreUploadOptions()
  @Published var appStoreUploadStatus = ""
  @Published var appStoreUploadError: String?
  @Published var appStoreUploadArchiveInspection: AppStoreArchiveInspection?
  @Published var appStoreUploadArchiveURL: URL?
  @Published var appStoreReleasePhase: AppStoreReleasePhase = .idle
  @Published var appStoreReleaseStatus = ""
  @Published var appStoreReleaseError: String?
  @Published var isPreparingFeedbackAgentTask = false
  @Published var designPreview = false
  @Published var pendingAgentPermission: AgentPermissionRequest?
  @Published var startDevServerOnRun = true
  @Published var terminalEntries: [TerminalEntry] = []
  @Published public var isTerminalExpanded = false
  @Published var evidenceWorkspaceTab: EvidenceWorkspaceTab = .evidence
  @Published public var isEvidenceWorkspaceOpen = false
  let simulatorLiveSession = SimulatorLiveSession()

  var selectedDestination: Destination? {
    destinations.first { $0.udid == selectedDestinationID }
  }
  var selectedAppStoreApp: AppStoreApp? {
    if let appStoreSelectedAppID {
      return appStoreApps.first { $0.id == appStoreSelectedAppID }
    }
    guard let bundleID = appStoreDistributionTarget?.bundleID ?? selectedTarget?.bundleID else {
      return nil
    }
    return appStoreApps.first { $0.bundleID == bundleID }
  }
  var selectedAppStoreVersion: AppStoreVersion? {
    appStoreVersions.first { $0.id == appStoreSelectedVersionID }
  }
  var selectedAppStoreBuild: AppStoreBuild? {
    appStoreBuilds.first { $0.id == appStoreSelectedBuildID }
  }
  var taskWorkspace: URL? { activeWorktree ?? repository }
  var canBuild: Bool {
    repository != nil && selectedContainer != nil && !selectedScheme.isEmpty
      && selectedDestination != nil && preflight?.isFullXcode == true && !isBusy
  }
  var canRun: Bool { canBuild && taskWorkspace != nil }
  var visibleChanges: [ProposedChange] {
    activeWorktree == nil ? repositoryChanges : proposedChanges
  }
  var changedFileCount: Int { visibleChanges.count }
  var isShowingTaskChanges: Bool { activeWorktree != nil }
  var verificationEvidence: [Evidence] {
    evidence.filter { $0.kind != .uiAction }
  }
  var isSemanticAutomationReady: Bool { wdaStatus.availability == .ready }
  var meaningfulHierarchyElements: [UIElement] {
    UIHierarchyInspector.meaningfulElements(from: hierarchyElements)
  }
  var requiresUIVerification: Bool {
    activeTaskIntent?.requiresRunningApp == true || (activeWorktree != nil && selectedTarget != nil)
  }
  var isExpoRepository: Bool { expoProjectRoot != nil }
  var expoProjectRoot: URL? {
    guard let workspace = taskWorkspace?.standardizedFileURL else { return nil }
    var candidate = taskContainer()?.deletingLastPathComponent().standardizedFileURL ?? workspace
    while candidate.path == workspace.path || candidate.path.hasPrefix(workspace.path + "/") {
      if Self.packageUsesExpo(at: candidate) { return candidate }
      guard candidate.path != workspace.path else { break }
      candidate.deleteLastPathComponent()
    }
    return Self.packageUsesExpo(at: workspace) ? workspace : nil
  }
  var needsExpoPreparation: Bool { isExpoRepository && containers.isEmpty }
  var agentComposerBlocker: String? {
    guard repository != nil else { return nil }
    let pendingIntent = AgentTaskIntentRouter.classify(taskPrompt)
    if pendingIntent.allowsSourceWrites && !isGitRepository {
      return "Editing requires a Git repository. Inspection and app testing remain available."
    }
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
  var hasAgentSession: Bool { activeACPSessionID != nil }
  var canStopAgent: Bool { hasAgentSession && isBusy }
  var displayedAgentConfigOptions: [ACPConfigOption] {
    agentConfigOptions.isEmpty ? localAgentConfigOptions : agentConfigOptions
  }
  var agentConfigCanChange: Bool {
    if hasAgentSession {
      return reportedAgentModelOption != nil || reportedAgentReasoningOption != nil
    }
    return localAgentConfigOptions.contains {
      (isModelOption($0) || isReasoningOption($0)) && !$0.options.isEmpty
    }
  }
  var agentConfigStatusText: String {
    if !hasAgentSession && !pendingAgentConfigValues.isEmpty {
      return "Will apply when the agent session connects"
    }
    if agentConfigCanChange {
      return hasAgentSession
        ? "CLI session controls" : "Local CLI setting · choose before connecting"
    }
    if hasAgentSession {
      return localAgentConfigOptions.isEmpty
        ? "This CLI did not report model or reasoning controls."
        : "Session controls unavailable · showing the local CLI setting"
    }
    return localAgentConfigOptions.isEmpty
      ? "Connect the agent to load model and reasoning controls"
      : "Local CLI setting · connect to change"
  }
  var canSendAgentPrompt: Bool {
    repository != nil
      && !taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && agentComposerBlocker == nil && !isBusy
  }
  var agentModelOption: ACPConfigOption? {
    reportedAgentModelOption ?? localAgentConfigOptions.first(where: isModelOption)
  }
  var agentReasoningOption: ACPConfigOption? {
    reportedAgentReasoningOption ?? localAgentConfigOptions.first(where: isReasoningOption)
  }
  var agentModelLabel: String {
    agentConfigValueLabel(for: agentModelOption) ?? "Model not reported"
  }
  var agentReasoningLabel: String {
    agentConfigValueLabel(for: agentReasoningOption) ?? "Reasoning not reported"
  }

  func canChangeAgentConfigOption(_ option: ACPConfigOption) -> Bool {
    guard !option.options.isEmpty else { return false }
    if hasAgentSession {
      return agentConfigOptions.contains(where: { $0.id == option.id })
    }
    return localAgentConfigOptions.contains(where: { $0.id == option.id })
  }

  private var reportedAgentModelOption: ACPConfigOption? {
    agentConfigOptions.first(where: isModelOption)
  }
  private var reportedAgentReasoningOption: ACPConfigOption? {
    agentConfigOptions.first(where: isReasoningOption)
  }

  private var baseline: BaselineManifest?
  private let workspaceManager = WorkspaceManager()
  private let runtime = RuntimeController()
  let appStoreCredentialSession = AppStoreCredentialSession()
  private let runner = ProcessRunner()
  private let metroRunner = ProcessRunner()
  private let appStoreDistributionRunner = ProcessRunner()
  private let taskRoot: URL
  private let runtimeRoot: URL
  private let deploymentRoot: URL
  private let adapterRoot: URL
  private let wdaRoot: URL
  let appStoreMetadataStore: SQLiteStore?
  private let wdaInstaller = WDAInstaller()
  private var activeACPClient: ACPClient?
  private var activeACPSessionID: String?
  private var runtimeEventObserverTask: Task<Void, Never>?
  private var runtimeEventSequence = 0
  private var metroTask: Task<ProcessOutcome, Error>?
  private var metroRunID: UUID?
  private var metroWorkspace: URL?
  private var metroExitDiagnostic: String?
  private var metroTerminalID: UUID?
  private var metroShouldStayRunning = false
  private var metroRecoveryTask: Task<Void, Never>?
  private var repositoryLoadTask: Task<Void, Never>?
  private var repositoryLoadID = UUID()
  private var permissionContinuation: CheckedContinuation<RPCEnvelope, Never>?
  private var pendingPermissionRPCID: RPCID?
  private var pendingPermissionFingerprint: String?
  private var persistentPermissionChoices: [String: String] = [:]
  private var didRecordRoutineTestingPermission = false
  private var agentMessageTimelineID: UUID?
  private var agentMessageProtocolID: String?
  private var agentMessageBuffer = ""
  private var agentMessageFlushTask: Task<Void, Never>?
  private var agentToolContexts: [String: AgentToolContext] = [:]
  private var agentToolTimelineIDs: [String: UUID] = [:]
  private var pendingAgentConfigValues: [String: String] = [:]
  var pendingAgentPromptAttachments: [ACPContentBlock] = []
  private var pendingPreviewInteractions: [PreviewInteractionRequest] = []
  private var previewTapWorker: Task<Void, Never>?
  private var previewWarmupTask: Task<Void, Never>?
  private var previewSettleTask: Task<Void, Never>?
  private var previewFeedbackTask: Task<Void, Never>?
  private var previewSessionID = UUID()
  private var terminalOutputBuffers: [UUID: String] = [:]
  private var terminalFlushTask: Task<Void, Never>?
  private var agentStopRequested = false
  var appStoreUploadTask: Task<Void, Never>?
  private var simulatorWorkspaceObservers: [NSObjectProtocol] = []
  private var embeddedSimulatorSessionActive = false

  public init() {
    let support =
      (try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
        create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let root = support.appending(path: "Lys", directoryHint: .isDirectory)
    taskRoot = root.appending(path: "Tasks", directoryHint: .isDirectory)
    runtimeRoot = root.appending(path: "Runtime", directoryHint: .isDirectory)
    deploymentRoot = root.appending(path: "Deployments", directoryHint: .isDirectory)
    adapterRoot = root.appending(path: "Adapters", directoryHint: .isDirectory)
    wdaRoot = root.appending(path: "WebDriverAgent", directoryHint: .isDirectory)
    appStoreMetadataStore = try? SQLiteStore(
      url: root.appending(path: "Deployments/metadata.sqlite3"))
    adapters = AdapterManager.detect(managedRoot: adapterRoot)
    selectedAdapterID = adapters.first(where: { $0.executable != nil })?.id ?? ""
    localAgentConfigOptions = Self.readLocalAgentConfigOptions(
      for: adapters.first(where: { $0.id == selectedAdapterID }))
    if ProcessInfo.processInfo.processName != "IOSDevSnapshot" {
      let workspaceNotifications = NSWorkspace.shared.notificationCenter
      for name in [
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didActivateApplicationNotification,
      ] {
        simulatorWorkspaceObservers.append(
          workspaceNotifications.addObserver(forName: name, object: nil, queue: .main) {
            [weak self] notification in
            guard
              let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            else { return }
            Task { @MainActor [weak self] in
              guard self?.embeddedSimulatorSessionActive == true else { return }
              self?.suppressExternalSimulatorWindow(application)
            }
          })
      }
    }
    Task {
      await refreshToolchain()
      await refreshRecovery()
      await loadAppStoreConnection()
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

  func saveTestSecret(id: String, value: String) {
    let identifier = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !identifier.isEmpty, !value.isEmpty,
      identifier.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.contains($0)
          || CharacterSet(charactersIn: "._-").contains($0)
      })
    else {
      notice = "Use a dot-separated secret ID and provide a non-empty value."
      return
    }
    do {
      try BlueprintSecretStore.write(value, account: identifier)
      testSecretIDs = BlueprintSecretStore.accounts()
      notice = "Saved \(identifier) in Keychain. The value is never shown to agents."
    } catch {
      notice = error.localizedDescription
    }
  }

  func deleteTestSecret(id: String) {
    do {
      try BlueprintSecretStore.delete(account: id)
      testSecretIDs = BlueprintSecretStore.accounts()
      notice = "Removed \(id) from Keychain."
    } catch {
      notice = error.localizedDescription
    }
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
    repositoryLoadTask?.cancel()
    repositoryLoadID = UUID()
    resetPreviewInteraction()
    let loadID = repositoryLoadID
    let openedRepository = url.resolvingSymlinksInPath().standardizedFileURL
    disableMetroPersistence()
    cancelOwnedMetro()
    activeACPClient?.cancel()
    activeACPClient = nil
    activeACPSessionID = nil
    runtimeEventObserverTask?.cancel()
    runtimeEventObserverTask = nil
    agentConfigOptions = []
    resolveAgentPermission(optionID: nil)
    resetAgentPresentation()
    repository = openedRepository
    isGitRepository = false
    branchName = ""
    activeWorktree = nil
    baseline = nil
    proposedChanges = []
    proposedChangesRevision += 1
    repositoryChanges = []
    repositoryChangesRevision += 1
    applyConflicts = []
    evidence = []
    verificationReport = nil
    taskSummary = nil
    setCurrentScreenshot(nil)
    selectedTarget = nil
    selectedElement = nil
    hierarchyElements = []
    generation = 0
    activeTaskIntent = nil
    activeJourney = nil
    terminalEntries = []
    terminalOutputBuffers = [:]
    terminalFlushTask?.cancel()
    terminalFlushTask = nil
    isTerminalExpanded = false
    appOperation = .idle
    containers = ToolchainDiscovery.projectContainers(in: openedRepository)
    selectedContainer = containers.first
    prepareAppStoreForProjectIdentityChange()
    files = Self.children(of: openedRepository)
    selectedFile = nil
    source = ""
    taskTitle = ""
    timeline = [
      .init(
        time: Self.now(), title: "Repository opened", detail: openedRepository.path,
        state: .complete),
      .init(
        time: "—", title: "Describe a task to begin",
        detail: "Editable agent work will be isolated from this checkout.", state: .waiting),
    ]
    plan = []
    status = "Discovering"
    repositoryLoadTask = Task {
      _ = try? await runtime.request(method: "devserver.stop")
      await runtime.stop()
      guard !Task.isCancelled, repositoryLoadID == loadID,
        repository == openedRepository
      else { return }
      await loadRepository(openedRepository, loadID: loadID)
    }
  }

  func selectContainer(_ url: URL) {
    resetPreviewInteraction()
    selectedContainer = url
    prepareAppStoreForProjectIdentityChange()
    selectedTarget = nil
    selectedElement = nil
    hierarchyElements = []
    setCurrentScreenshot(nil)
    Task { await refreshProjectSelection() }
  }

  func selectScheme(_ scheme: String) {
    resetPreviewInteraction()
    selectedScheme = scheme
    prepareAppStoreForProjectIdentityChange()
    selectedTarget = nil
    selectedElement = nil
    hierarchyElements = []
    setCurrentScreenshot(nil)
  }

  func selectDestination(_ id: String) {
    resetPreviewInteraction()
    selectedDestinationID = id
    selectedTarget = nil
    refreshWDAStatus()
  }

  func refreshSimulators() {
    Task { await refreshDestinations() }
  }

  public func toggleTerminal() {
    isTerminalExpanded.toggle()
    if isTerminalExpanded { evidenceWorkspaceTab = .terminal }
  }

  public func toggleEvidenceWorkspace() {
    isEvidenceWorkspaceOpen.toggle()
  }

  func clearTerminal() {
    guard !terminalEntries.contains(where: { $0.state == .running }) else { return }
    terminalEntries = []
  }

  func clearAgentActivity() {
    guard !isBusy, pendingAgentPermission == nil else { return }
    timeline.removeAll { $0.category != .system }
  }

  func prepareExpoProject() {
    guard let repository, needsExpoPreparation, !isBusy, appOperation == .idle else {
      notice = "Wait for the current build, test, or preparation operation to finish."
      return
    }
    let confirmation = NSAlert()
    confirmation.messageText = "Prepare this Expo project for iOS?"
    confirmation.informativeText =
      "Lys will run npm ci when node_modules is missing, then npm exec -- expo prebuild --platform ios. This executes the repository's package scripts and may download dependencies."
    confirmation.addButton(withTitle: "Prepare iOS Project")
    confirmation.addButton(withTitle: "Cancel")
    guard confirmation.runModal() == .alertFirstButtonReturn else { return }
    guard let npm = npmExecutable() else {
      notice = "npm was not found. Install Node.js, then reopen Lys."
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
        let coordinator = WorkspaceOperationCoordinator(workspace: repository)
        let lease = try await coordinator.acquire(.expoPrebuild, wait: false)
        defer { lease.release() }
        let environment = ["PATH": executableSearchPath()]
        if !FileManager.default.fileExists(atPath: repository.appending(path: "node_modules").path)
        {
          status = "Installing JavaScript dependencies"
          let terminalID = beginTerminal(
            executable: npm.path, arguments: ["ci"], workingDirectory: repository)
          let install = try await runner.run(
            executable: npm, arguments: ["ci"], workingDirectory: repository,
            environment: environment, maximumOutputBytes: 24 * 1_024 * 1_024)
          finishTerminal(
            terminalID, succeeded: install.succeeded, output: install.stdout + install.stderr)
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
        let terminalID = beginTerminal(
          executable: npm.path,
          arguments: ["exec", "--", "expo", "prebuild", "--platform", "ios"],
          workingDirectory: repository)
        let prebuild = try await runner.run(
          executable: npm,
          arguments: ["exec", "--", "expo", "prebuild", "--platform", "ios"],
          workingDirectory: repository, environment: environment,
          maximumOutputBytes: 32 * 1_024 * 1_024)
        finishTerminal(
          terminalID, succeeded: prebuild.succeeded, output: prebuild.stdout + prebuild.stderr)
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
        files = Self.children(of: repository)
        lease.release()
        await refreshProjectSelection()
        status = "Expo iOS project ready"
        timeline.append(
          .init(
            time: Self.now(), title: "iOS project generated",
            detail: first.path, state: .complete))
      } catch let error as WorkspaceOperationBusyError {
        status = "Expo setup blocked"
        notice = error.localizedDescription
        timeline.append(
          .init(
            time: Self.now(), title: "Expo setup blocked", detail: error.localizedDescription,
            state: .warning))
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
    agentConfigOptions = []
    pendingAgentConfigValues = [:]
    localAgentConfigOptions = Self.readLocalAgentConfigOptions(
      for: adapters.first(where: { $0.id == selectedAdapterID }))
  }

  func selectAgentAdapter(_ id: String) {
    guard adapters.contains(where: { $0.id == id && $0.executable != nil }) else { return }
    guard selectedAdapterID != id else { return }
    activeACPClient?.cancel()
    activeACPClient = nil
    activeACPSessionID = nil
    agentConfigOptions = []
    pendingAgentConfigValues = [:]
    selectedAdapterID = id
    localAgentConfigOptions = Self.readLocalAgentConfigOptions(
      for: adapters.first(where: { $0.id == id }))
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
    guard let repository,
      !taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      activeWorktree == nil
    else { return }
    let prompt = taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let intent = AgentTaskIntentRouter.classify(prompt)
    guard !intent.allowsSourceWrites || isGitRepository else {
      notice =
        "Editing requires a Git repository. You can still ask the agent to inspect or test the running app."
      return
    }
    let promptAttachments = pendingAgentPromptAttachments
    pendingAgentPromptAttachments = []
    taskPrompt = ""
    taskTitle = prompt
    activeTaskIntent = intent
    activeJourney = nil
    taskSummary = nil
    agentStopRequested = false
    generation = 0
    status = "Preparing task"
    isBusy = true
    plan = hostPlan(for: intent)
    timeline.append(
      .init(
        time: Self.now(), title: "You", detail: prompt, state: .complete,
        category: .human))
    timeline.append(
      .init(
        time: Self.now(), title: "Task routed",
        detail: intentSummary(intent), state: .complete))
    Task {
      do {
        let workspace: URL
        if intent.workspacePolicy == .isolatedWorktree {
          let prepared = try await workspaceManager.createTask(
            repository: repository, taskRoot: taskRoot)
          activeWorktree = prepared.worktree
          baseline = prepared.manifest
          files = Self.children(of: prepared.worktree)
          selectedFile = nil
          source = ""
          workspace = prepared.worktree
          plan[0].state = .complete
          timeline.append(
            .init(
              time: Self.now(), title: "Isolated task ready", detail: prepared.worktree.path,
              state: .complete))
        } else {
          workspace = repository
          plan[0].state = .complete
          timeline.append(
            .init(
              time: Self.now(), title: "Current app session selected",
              detail: "No worktree or source mutation is allowed for this task.", state: .complete))
        }
        plan[1].state = .active
        try await ensureRuntimeForTask(workspace: workspace)
        try await configureRuntime(intent: intent)
        plan[1].state = .complete
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
        let flowIncomplete = try await connectAgent(
          adapter: adapter, workspace: workspace, prompt: prompt, intent: intent,
          attachments: promptAttachments)
        guard !agentStopRequested else { return }
        plan[2].state = .complete
        if flowIncomplete {
          await finishIncompleteTestingSession()
          return
        }
        status =
          intent.allowsSourceWrites
          ? "Agent finished · review evidence" : "Testing finished · review evidence"
        if intent.allowsSourceWrites { try await refreshProposedChanges() }
        await refreshEvidence()
        await createTaskSummary()
      } catch {
        if agentStopRequested {
          status = "Agent stopped"
          await createTaskSummary(stopped: true)
        } else {
          if activeWorktree == nil {
            status = "Task failed"
          } else {
            status = "Task needs attention"
          }
          notice = error.localizedDescription
          timeline.append(
            .init(
              time: Self.now(), title: "Task preparation failed",
              detail: error.localizedDescription, state: .warning))
        }
        if plan.indices.contains(2), plan[2].state == .active { plan[2].state = .blocked }
        if activeWorktree == nil, plan.indices.contains(0) { plan[0].state = .blocked }
      }
      isBusy = false
    }
  }

  private func hostPlan(for intent: AgentTaskIntent) -> [TaskPlanItem] {
    switch intent.kind {
    case .verifyCurrentApp:
      return [
        .init(title: "Attach to the current app", state: .active),
        .init(title: "Configure the semantic testing session", state: .waiting),
        .init(title: "Connect the selected agent", state: .waiting),
        .init(title: "Run the app journey and assertions", state: .waiting),
        .init(title: "Validate current evidence", state: .waiting),
      ]
    case .inspectCurrentApp:
      return [
        .init(title: "Attach to the current app", state: .active),
        .init(title: "Configure read-only inspection", state: .waiting),
        .init(title: "Connect the selected agent", state: .waiting),
        .init(title: "Inspect the semantic interface", state: .waiting),
        .init(title: "Present captured evidence", state: .waiting),
      ]
    case .runTests:
      return [
        .init(title: "Use the current checkout", state: .active),
        .init(title: "Configure the test runner", state: .waiting),
        .init(title: "Connect the selected agent", state: .waiting),
        .init(title: "Run selected tests", state: .waiting),
        .init(title: "Validate test evidence", state: .waiting),
      ]
    case .modifyAndVerify:
      return [
        .init(title: "Create isolated worktree", state: .active),
        .init(title: "Configure the task runtime", state: .waiting),
        .init(title: "Connect the selected agent", state: .waiting),
        .init(title: "Build only if the mutation requires it", state: .waiting),
        .init(title: "Run journey, review, and apply", state: .waiting),
      ]
    }
  }

  private func intentSummary(_ intent: AgentTaskIntent) -> String {
    switch intent.kind {
    case .verifyCurrentApp:
      "Verify current app · preserve runtime · build only if missing · read-only source"
    case .inspectCurrentApp:
      "Inspect current app · preserve runtime · read-only source"
    case .runTests:
      "Run source tests · no Simulator lifecycle · read-only source"
    case .modifyAndVerify:
      "Modify and verify · isolated worktree · build only when stale"
    }
  }

  private func agentContext(prompt: String, workspace: URL, intent: AgentTaskIntent) -> String {
    let sourcePolicy =
      intent.allowsSourceWrites
      ? "Source edits are allowed only inside the isolated worktree at \(workspace.path)."
      : "This is a read-only source session at \(workspace.path). Do not edit files or create a build unless the host-owned journey reports that no compatible app exists."
    let journeyPolicy =
      intent.requiresRunningApp
      ? "Call flow.list. If it returns a matching Lys flow, call flow.run once with its exact flowID and required parameters; the host normalizes independent flows before execution, owns navigation from the normalized context to the flow start, authenticated-session setup, every interaction, loops, all acceptance criteria, evidence, and terminal completion. Do not pre-navigate or require the user to leave the app on a particular screen. If no declared flow matches the requested goal, state that the run is exploratory, then call flow.run without flowID; a new exploratory journey is also normalized, while continuing the same journey preserves its state. Continue only through host-returned actions. Never invent selectors, coordinates, routes, or actions. Never start, stop, install, terminate, or rebuild app infrastructure yourself. Before ending, call evidence.summary and give the user a short summary of what ran, what passed, and what remains."
      : "Use only test.list and test.run with the host-selected project context. Do not start Simulator or app lifecycle operations."
    return """
      \(prompt)

      Host-classified intent: \(intent.kind.rawValue).
      \(sourcePolicy)
      \(journeyPolicy)
      The selected scheme is \(selectedScheme.isEmpty ? "not selected" : selectedScheme), and the selected Simulator is \(selectedDestination?.name ?? "not selected"). Tool results contain structuredContent; use it instead of parsing display text. Do not claim completion from prose. Completion requires fresh host-recorded evidence for the active generation.
      """
  }

  func sendAgentPrompt() {
    guard canSendAgentPrompt else { return }
    if activeACPSessionID == nil {
      startTask()
      return
    }
    let pendingIntent = AgentTaskIntentRouter.classify(taskPrompt)
    if let activeTaskIntent,
      pendingIntent.allowsSourceWrites && !activeTaskIntent.allowsSourceWrites
    {
      activeACPClient?.cancel()
      activeACPClient = nil
      activeACPSessionID = nil
      agentConfigOptions = []
      activeJourney = nil
      self.activeTaskIntent = nil
      timeline.append(
        .init(
          time: Self.now(), title: "Starting an editable task",
          detail: "The read-only testing session was closed before creating an isolated worktree.",
          state: .complete))
      startTask()
      return
    }
    guard let client = activeACPClient, let sessionID = activeACPSessionID else { return }
    let prompt = taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let promptAttachments = pendingAgentPromptAttachments
    pendingAgentPromptAttachments = []
    taskPrompt = ""
    isBusy = true
    status = "Agent working"
    agentStopRequested = false
    timeline.append(
      .init(
        time: Self.now(), title: "You", detail: prompt, state: .complete,
        category: .human))
    Task {
      do {
        _ = try? await runtime.request(method: "session.resume")
        let result = try await client.request(
          method: "session/prompt",
          params: try jsonValue(
            ACPPrompt(
              sessionID: sessionID,
              content: [.init(text: prompt)] + promptAttachments)))
        let reason = result.result?["stopReason"]?.stringValue ?? "completed"
        guard !agentStopRequested else { return }
        finishAgentMessage()
        timeline.append(
          .init(
            time: Self.now(), title: "Agent response ended", detail: "Stop reason: \(reason)",
            state: activeTaskIntent?.kind == .verifyCurrentApp ? .warning : .complete))
        let flowIncomplete = try await continueIncompleteTestingSession()
        if flowIncomplete {
          await finishIncompleteTestingSession()
          return
        }
        if activeTaskIntent?.allowsSourceWrites == true { try await refreshProposedChanges() }
        await refreshEvidence()
        await createTaskSummary()
        status =
          activeTaskIntent?.allowsSourceWrites == true
          ? "Agent finished · review evidence" : "Testing finished · review evidence"
      } catch {
        finishAgentMessage()
        if agentStopRequested {
          status = "Agent stopped"
          await createTaskSummary(stopped: true)
        } else {
          status = "Agent needs attention"
          notice = error.localizedDescription
          timeline.append(
            .init(
              time: Self.now(), title: "Agent turn failed", detail: error.localizedDescription,
              state: .warning))
        }
      }
      isBusy = false
    }
  }

  func setAgentConfigOption(_ option: ACPConfigOption, value: ACPConfigOptionValue) {
    guard let client = activeACPClient, let sessionID = activeACPSessionID else {
      guard let key = agentConfigKey(for: option) else {
        notice = "Connect the agent session before changing this setting."
        return
      }
      pendingAgentConfigValues[key] = value.value
      if let index = localAgentConfigOptions.firstIndex(where: { $0.id == option.id }) {
        var updated = localAgentConfigOptions
        updated[index].currentValue = .string(value.value)
        localAgentConfigOptions = updated
      }
      return
    }
    Task {
      do {
        let result = try await client.request(
          method: "session/set_config_option",
          params: .object([
            "sessionId": .string(sessionID),
            "configId": .string(option.id),
            "value": .string(value.value),
          ]))
        updateAgentConfigOptions(
          result.result?["configOptions"] ?? result.result?["config_options"])
      } catch {
        notice = "Could not update \(option.name.lowercased()): \(error.localizedDescription)"
      }
    }
  }

  func build() {
    guard canBuild else {
      notice = preflight?.issues.joined(separator: "\n") ?? "Choose a scheme and simulator first."
      return
    }
    guard approveRequiredCocoaPodsInstall() else { return }
    isBusy = true
    appOperation = .preparing
    Task {
      do {
        try await installRequiredCocoaPods()
        guard approveRequiredExpoCompatibilityRepair() else {
          isBusy = false
          appOperation = .idle
          return
        }
      } catch {
        isBusy = false
        appOperation = .idle
        status = "Dependency preparation failed"
        notice = error.localizedDescription
        timeline.append(
          .init(
            time: Self.now(), title: "Dependency preparation failed",
            detail: error.localizedDescription, state: .warning))
        return
      }
      isBusy = false
      _ = await executeBuild()
    }
  }

  func run() {
    guard canRun else {
      notice = "Choose a buildable scheme and simulator first."
      return
    }
    guard approveRequiredCocoaPodsInstall() else { return }
    resetPreviewInteraction()
    selectedTarget = nil
    selectedElement = nil
    hierarchyElements = []
    setCurrentScreenshot(nil)
    isBusy = true
    appOperation = isExpoRepository && startDevServerOnRun ? .preparing : .building
    Task {
      do {
        try await installRequiredCocoaPods()
        guard approveRequiredExpoCompatibilityRepair() else {
          isBusy = false
          appOperation = .idle
          return
        }
        if isExpoRepository && startDevServerOnRun {
          metroShouldStayRunning = true
          try await ensureMetro()
        }
      } catch {
        isBusy = false
        appOperation = .idle
        status = "Preparation failed"
        notice = error.localizedDescription
        timeline.append(
          .init(
            time: Self.now(), title: "Run preparation failed",
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
        if isExpoRepository && startDevServerOnRun {
          metroShouldStayRunning = true
          try await ensureMetro()
        }
        try await ensureRuntime()
        _ = try? await runtime.request(
          method: "app.terminate",
          params: .object([
            "udid": .string(destination.udid), "bundleID": .string(target.bundleID),
          ]))
        let refreshed = try await runtime.request(
          method: "app.install_launch",
          params: .object([
            "udid": .string(destination.udid), "appPath": .string(productPath.path),
            "bundleID": .string(target.bundleID),
            "runtime": .string(destination.runtime),
            "startDevServer": .bool(false),
            "useDevServer": .bool(isExpoRepository && startDevServerOnRun),
          ]))
        guard refreshed["launched"]?.boolValue == true else {
          throw RPCError(code: -32053, message: "The refreshed app did not launch")
        }
        warmPreviewInteraction(destination: destination, target: target)
        beginLiveSimulatorSession(destination: destination)
        status = "Waiting for app to settle"
        await captureScreenshot(settleDelayMS: isExpoRepository ? 2_500 : 900)
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
    agentStopRequested = true
    Task {
      if let sessionID = activeACPSessionID {
        try? activeACPClient?.notify(
          method: "session/cancel",
          params: .object(["sessionId": .string(sessionID)]))
      }
      resolveAgentPermission(optionID: nil)
      _ = try? await runtime.request(method: "build.cancel")
      disableMetroPersistence()
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

  func stopAgent() {
    guard canStopAgent else { return }
    agentStopRequested = true
    Task {
      if let sessionID = activeACPSessionID {
        try? activeACPClient?.notify(
          method: "session/cancel",
          params: .object(["sessionId": .string(sessionID)]))
      }
      _ = try? await runtime.request(method: "session.stop")
      resolveAgentPermission(optionID: nil)
      finishAgentMessage()
      isBusy = false
      status = "Agent stopped"
      timeline.append(
        .init(
          time: Self.now(), title: "Agent stopped",
          detail: "The running app and development server were preserved.", state: .warning))
      await createTaskSummary(stopped: true)
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
      notice = "Build and run the app before interacting with the embedded Simulator."
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
    let x = min(max(normalizedX, 0), 1)
    let y = min(max(normalizedY, 0), 1)
    let feedback = PreviewTapFeedback(x: x, y: y)
    previewTapFeedback = feedback
    previewFeedbackTask?.cancel()
    previewFeedbackTask = Task {
      try? await Task.sleep(for: .milliseconds(140))
      guard !Task.isCancelled, previewTapFeedback?.id == feedback.id else { return }
      previewTapFeedback = nil
    }
    previewSettleTask?.cancel()
    previewSettleTask = nil
    pendingPreviewInteractions.append(
      .tap(PreviewTapRequest(x: x, y: y, sessionID: previewSessionID)))
    previewInteractionState = .sending
    guard previewTapWorker == nil else { return }
    previewTapWorker = Task {
      await processPreviewInteractions(destination: destination, target: target)
    }
  }

  func swipePreview(
    startX: Double, startY: Double, endX: Double, endY: Double
  ) {
    guard let destination = selectedDestination, let target = selectedTarget else {
      notice = "Build and run the app before interacting with the embedded Simulator."
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
    previewSettleTask?.cancel()
    previewSettleTask = nil
    pendingPreviewInteractions.append(
      .swipe(
        PreviewSwipeRequest(
          startX: min(max(startX, 0), 1), startY: min(max(startY, 0), 1),
          endX: min(max(endX, 0), 1), endY: min(max(endY, 0), 1),
          sessionID: previewSessionID)))
    previewInteractionState = .sending
    guard previewTapWorker == nil else { return }
    previewTapWorker = Task {
      await processPreviewInteractions(destination: destination, target: target)
    }
  }

  private func processPreviewInteractions(destination: Destination, target: AppTarget) async {
    do {
      try await ensureRuntime()
      while let request = pendingPreviewInteractions.first {
        pendingPreviewInteractions.removeFirst()
        guard request.sessionID == previewSessionID,
          selectedDestinationID == destination.udid,
          selectedTarget?.bundleID == target.bundleID
        else { continue }

        let started = DispatchTime.now().uptimeNanoseconds
        let action: String
        let coordinate: JSONValue
        let previewCaptureLeadMS: Int
        switch request {
        case .tap(let tap):
          action = "tap"
          previewCaptureLeadMS = 180
          coordinate = .object([
            "x": .number(tap.x), "y": .number(tap.y),
          ])
        case .swipe(let swipe):
          action = "swipe"
          previewCaptureLeadMS = 320
          coordinate = .object([
            "startX": .number(swipe.startX), "startY": .number(swipe.startY),
            "endX": .number(swipe.endX), "endY": .number(swipe.endY),
            "durationMS": .number(350),
          ])
        }
        async let performed: JSONValue = runtime.request(
          method: "ui.perform",
          params: .object([
            "udid": .string(destination.udid), "bundleID": .string(target.bundleID),
            "runtime": .string(destination.runtime),
            "selector": .object(["coordinate": coordinate]),
            "action": .string(action),
          ]))

        // Begin the cheap frame capture near the end of XCTest's gesture instead of waiting for
        // its HTTP acknowledgement. This overlaps independent Simulator work and removes another
        // frame of perceived latency. The settle refresh below corrects any mid-animation frame.
        try? await Task.sleep(for: .milliseconds(previewCaptureLeadMS))
        guard pendingPreviewInteractions.isEmpty else {
          _ = try await performed
          continue
        }
        async let capturedFrame: JSONValue = runtime.request(
          method: "preview.capture",
          params: .object(["udid": .string(destination.udid)]))
        _ = try await performed

        // Rapid gestures are delivered without waiting for an intermediate screenshot. Once the
        // queue drains, one cheap frame replaces the preview without running verification.
        guard pendingPreviewInteractions.isEmpty else { continue }
        let frame = try await capturedFrame
        guard request.sessionID == previewSessionID,
          selectedDestinationID == destination.udid,
          selectedTarget?.bundleID == target.bundleID,
          let path = frame["path"]?.stringValue
        else { continue }
        setCurrentScreenshot(URL(fileURLWithPath: path))
        previewLatencyMS = Int(
          (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        schedulePreviewSettleFrame(
          sessionID: request.sessionID, destination: destination, target: target)
      }
      if selectedDestinationID == destination.udid, selectedTarget?.bundleID == target.bundleID {
        previewInteractionState = .ready
      }
    } catch {
      if selectedDestinationID == destination.udid, selectedTarget?.bundleID == target.bundleID {
        previewInteractionState = .unavailable
        notice = "Embedded Simulator interaction failed: \(error.localizedDescription)"
      }
    }
    previewTapWorker = nil
    if !pendingPreviewInteractions.isEmpty, let destination = selectedDestination,
      let target = selectedTarget
    {
      previewInteractionState = .sending
      previewTapWorker = Task {
        await processPreviewInteractions(destination: destination, target: target)
      }
    }
  }

  /// Publishes one post-animation frame without delaying the immediate response to the gesture.
  /// A new gesture cancels this refresh, so rapid use never builds a screenshot backlog.
  private func schedulePreviewSettleFrame(
    sessionID: UUID, destination: Destination, target: AppTarget
  ) {
    previewSettleTask?.cancel()
    previewSettleTask = Task {
      try? await Task.sleep(for: .milliseconds(140))
      guard !Task.isCancelled, sessionID == previewSessionID,
        selectedDestinationID == destination.udid,
        selectedTarget?.bundleID == target.bundleID,
        pendingPreviewInteractions.isEmpty,
        previewTapWorker == nil
      else { return }
      guard
        let frame = try? await runtime.request(
          method: "preview.capture",
          params: .object(["udid": .string(destination.udid)])),
        !Task.isCancelled, sessionID == previewSessionID,
        let path = frame["path"]?.stringValue
      else { return }
      setCurrentScreenshot(URL(fileURLWithPath: path))
      previewSettleTask = nil
    }
  }

  private func warmPreviewInteraction(destination: Destination, target: AppTarget) {
    guard wdaStatus.availability == .ready else {
      previewInteractionState = .unavailable
      return
    }
    previewWarmupTask?.cancel()
    let sessionID = previewSessionID
    previewInteractionState = .warming
    previewWarmupTask = Task {
      do {
        try await ensureRuntime()
        _ = try await runtime.request(
          method: "ui.prepare",
          params: .object([
            "udid": .string(destination.udid), "bundleID": .string(target.bundleID),
            "runtime": .string(destination.runtime),
          ]))
        guard !Task.isCancelled, sessionID == previewSessionID,
          selectedDestinationID == destination.udid,
          selectedTarget?.bundleID == target.bundleID
        else { return }
        previewInteractionState = .ready
      } catch {
        guard !Task.isCancelled, sessionID == previewSessionID else { return }
        previewInteractionState = .unavailable
      }
    }
  }

  private func beginLiveSimulatorSession(destination: Destination) {
    embeddedSimulatorSessionActive = true
    suppressExternalSimulatorWindows()
    let sessionID = previewSessionID
    Task {
      do {
        try await ensureRuntime()
        let frame = try await runtime.request(
          method: "preview.capture",
          params: .object(["udid": .string(destination.udid)]))
        guard sessionID == previewSessionID,
          selectedDestinationID == destination.udid,
          let path = frame["path"]?.stringValue,
          let image = NSImage(contentsOfFile: path),
          let representation = image.representations.max(by: {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
          }),
          representation.pixelsWide > 0, representation.pixelsHigh > 0
        else { return }
        setCurrentScreenshot(URL(fileURLWithPath: path))
        simulatorLiveSession.start(
          udid: destination.udid, nativePixelWidth: representation.pixelsWide,
          nativePixelHeight: representation.pixelsHigh,
          developerDirectory: developerDirectory)
      } catch {
        // Evidence screenshots remain available if the optional continuous stream cannot start.
      }
    }
  }

  private func resetPreviewInteraction() {
    embeddedSimulatorSessionActive = false
    simulatorLiveSession.stop()
    previewTapWorker?.cancel()
    previewWarmupTask?.cancel()
    previewSettleTask?.cancel()
    previewFeedbackTask?.cancel()
    previewTapWorker = nil
    previewWarmupTask = nil
    previewSettleTask = nil
    previewFeedbackTask = nil
    pendingPreviewInteractions = []
    previewTapFeedback = nil
    previewLatencyMS = nil
    previewSessionID = UUID()
    previewInteractionState = .unavailable
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
    status = "Capturing screenshot"
    Task {
      if await captureScreenshot() {
        status = "Screenshot captured"
      } else {
        status = "Screenshot failed"
      }
    }
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
        proposedChangesRevision += 1
        status = "Review"
        if plan.indices.contains(4) { plan[4].state = .active }
      } catch { notice = error.localizedDescription }
    }
  }

  func refreshRepositoryChanges() async {
    guard let repository, isGitRepository else {
      repositoryChanges = []
      repositoryChangesRevision += 1
      return
    }
    do {
      let changes = try await workspaceManager.repositoryChanges(repository: repository)
      guard self.repository == repository else { return }
      repositoryChanges = changes
      repositoryChangesRevision += 1
    } catch {
      notice = error.localizedDescription
    }
  }

  func proposedDiff(for change: ProposedChange) async -> ProposedFileDiff? {
    if designPreview { return Self.previewDiff(for: change) }
    guard let activeWorktree, let baseline else { return nil }
    return try? await workspaceManager.proposedDiff(
      worktree: activeWorktree, baseline: baseline, change: change)
  }

  func repositoryDiff(for change: ProposedChange) async -> ProposedFileDiff? {
    if designPreview { return Self.previewDiff(for: change) }
    guard let repository else { return nil }
    return try? await workspaceManager.repositoryDiff(repository: repository, change: change)
  }

  private static func previewDiff(for change: ProposedChange) -> ProposedFileDiff {
    if change.binary {
      return .init(
        path: change.path, kind: change.kind, binary: true, lines: [], addedLineCount: 0,
        removedLineCount: 0, message: "Binary file · line diff unavailable")
    }

    let sampleLines: [(ProposedDiffLineKind, Int?, Int?, String)]
    switch change.path {
    case "ProfileView.swift":
      sampleLines = [
        (.context, 1, 1, "import SwiftUI"),
        (.context, 2, 2, ""),
        (.context, 3, 3, "struct ProfileView: View {"),
        (.removed, 4, nil, "  @State private var isEditing = false"),
        (.added, nil, 4, "  @State private var isEditing = false"),
        (.added, nil, 5, "  @State private var showsSavedState = false"),
        (.context, 5, 6, ""),
        (.context, 6, 7, "  var body: some View {"),
        (.removed, 7, nil, "    ProfileHeader(isEditing: $isEditing)"),
        (.added, nil, 8, "    ProfileHeader(isEditing: $isEditing, showsSavedState: showsSavedState)"),
        (.context, 8, 9, "  }"),
        (.context, 9, 10, "}"),
      ]
    case "ProfileTests.swift":
      sampleLines = [
        (.added, nil, 1, "import XCTest"),
        (.added, nil, 2, "@testable import TravelApp"),
        (.added, nil, 3, ""),
        (.added, nil, 4, "final class ProfileTests: XCTestCase {"),
        (.added, nil, 5, "  func testProfileSaveState() {"),
        (.added, nil, 6, "    XCTAssertTrue(ProfileViewModel().canSave)"),
        (.added, nil, 7, "  }"),
        (.added, nil, 8, "}"),
      ]
    default:
      sampleLines = [
        (.context, 1, 1, "// Preview diff for the isolated task"),
        (.removed, 2, nil, "let value = \"before\""),
        (.added, nil, 2, "let value = \"after\""),
      ]
    }
    let lines = sampleLines.enumerated().map { index, line in
      ProposedDiffLine(
        id: index, kind: line.0, oldLineNumber: line.1, newLineNumber: line.2, text: line.3)
    }
    return .init(
      path: change.path, kind: change.kind, binary: false, lines: lines,
      addedLineCount: lines.filter { $0.kind == .added }.count,
      removedLineCount: lines.filter { $0.kind == .removed }.count)
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
        await refreshRepositoryChanges()
      } catch { notice = error.localizedDescription }
    }
  }

  func discardTask() {
    guard let activeWorktree, let repository else { return }
    Task {
      do {
        disableMetroPersistence()
        await stopOwnedMetro()
        activeACPClient?.cancel()
        activeACPClient = nil
        activeACPSessionID = nil
        runtimeEventObserverTask?.cancel()
        runtimeEventObserverTask = nil
        agentConfigOptions = []
        resolveAgentPermission(optionID: nil)
        resetAgentPresentation()
        await runtime.stop()
        try await workspaceManager.discard(
          worktree: activeWorktree, repository: repository, taskRoot: taskRoot)
        self.activeWorktree = nil
        baseline = nil
        files = Self.children(of: repository)
        proposedChanges = []
        proposedChangesRevision += 1
        applyConflicts = []
        evidence = []
        verificationReport = nil
        taskTitle = ""
        activeTaskIntent = nil
        activeJourney = nil
        plan = []
        status = "Ready"
        await refreshRepositoryChanges()
      } catch { notice = error.localizedDescription }
    }
  }

  func resume(_ recovered: RecoverableWorkspace) {
    repositoryLoadTask?.cancel()
    repositoryLoadID = UUID()
    let loadID = repositoryLoadID
    let original = URL(fileURLWithPath: recovered.manifest.repositoryRoot)
    repository = original
    activeWorktree = recovered.worktree
    baseline = recovered.manifest
    isGitRepository = true
    containers = ToolchainDiscovery.projectContainers(in: original)
    selectedContainer = containers.first
    files = Self.children(of: recovered.worktree)
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
        await loadRepository(original, loadID: loadID)
        try await refreshProposedChanges()
        recoverableWorkspaces.removeAll { $0.id == recovered.id }
        status = "Recovered · review required"
      } catch {
        notice = error.localizedDescription
        status = "Recovery blocked"
      }
    }
  }

  private func suppressExternalSimulatorWindows() {
    for application in NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.apple.iphonesimulator")
    {
      suppressExternalSimulatorWindow(application)
    }
  }

  private func suppressExternalSimulatorWindow(_ application: NSRunningApplication) {
    guard embeddedSimulatorSessionActive, !application.isHidden else { return }
    _ = application.hide()
  }

  func exportDiagnostics() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "lys-diagnostics.json"
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
    activeACPSessionID = "synthetic-agent-session"
    repository = URL(fileURLWithPath: "/Synthetic/TravelApp")
    activeWorktree = URL(fileURLWithPath: "/Synthetic/Tasks/profile-dark-mode")
    isGitRepository = true
    branchName = "main"
    status = "Verifying"
    isBusy = true
    generation = 2
    terminalEntries = [
      TerminalEntry(
        command:
          "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -workspace /Synthetic/TravelApp.xcworkspace -scheme TravelApp build",
        workingDirectory: "/Synthetic/TravelApp", state: .succeeded)
    ]
    terminalEntries[0].output = "** BUILD SUCCEEDED **\n"
    isEvidenceWorkspaceOpen = ProcessInfo.processInfo.environment["LYS_SNAPSHOT_TERMINAL"] == "1"
    taskTitle =
      "Add dark mode support to the Profile screen and verify it on small and large iPhones."
    activeTaskIntent = AgentTaskIntentRouter.classify(taskTitle)
    var journey = JourneyRecord(goal: "Verify Profile appearance and navigation")
    journey.status = .running
    journey.steps = [
      .init(
        step: .init(id: "open-profile", title: "Open Profile", assertVisible: true),
        status: .passed, detail: "Profile heading is visible."),
      .init(
        step: .init(id: "open-appearance", title: "Open Appearance", assertVisible: true),
        status: .passed, detail: "Appearance is set to Dark."),
      .init(
        step: .init(id: "verify-large", title: "Verify on large iPhone", assertVisible: true),
        status: .running, detail: "Inspecting the current semantic screen."),
    ]
    journey.currentFingerprint = .init(digest: "9b3f81d219preview", owningApplication: "TravelApp")
    activeJourney = journey
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
        time: "10:42", title: "You",
        detail: "Add dark mode support to Profile and test it.", state: .complete,
        category: .human),
      .init(
        time: "10:42", title: "Lys",
        detail:
          "Got it. I’ll add dark mode to the Profile screen, update the related styles, and run tests to verify everything works.",
        state: .complete, category: .agent),
      .init(
        time: "10:44", title: "Edited files",
        detail: "ProfileView.swift, Theme.swift, Color+Theme.swift", state: .complete,
        category: .tool),
      .init(
        time: "10:46", title: "Build", detail: "Build succeeded", state: .complete,
        category: .tool),
      .init(
        time: "10:47", title: "Run tests", detail: "8 tests running on iPhone 16 Pro",
        state: .active, category: .tool),
      .init(
        time: "10:48", title: "Lys",
        detail:
          "The Profile checks passed. I’m verifying the final appearance and navigation state now.",
        state: .active, category: .agent),
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
    proposedChangesRevision += 1
    let previewRoot = activeWorktree ?? URL(fileURLWithPath: "/Synthetic/Tasks/profile-dark-mode")
    files = [
      FileNode(
        url: previewRoot.appending(path: "App", directoryHint: .isDirectory), isDirectory: true),
      FileNode(
        url: previewRoot.appending(path: "Assets", directoryHint: .isDirectory),
        isDirectory: true),
      FileNode(
        url: previewRoot.appending(path: "Components", directoryHint: .isDirectory),
        isDirectory: true),
      FileNode(url: previewRoot.appending(path: "README.md"), isDirectory: false),
      FileNode(url: previewRoot.appending(path: "package.json"), isDirectory: false),
    ]
    selectedFile = files[4].url
    source = """
      {
        "name": "travel-app",
        "main": "expo-router/entry",
        "version": "1.0.0",
        "scripts": {
          "start": "expo start",
          "ios": "expo run:ios",
          "test": "jest --watchAll"
        },
        "dependencies": {
          "@react-native-async-storage/async-storage": "^2.1.2",
          "expo": "53.0.22",
          "expo-router": "~5.1.5",
          "react": "19.0.0",
          "react-native": "0.79.5"
        },
        "private": true
      }
      """
  }

  public func loadTaskSummaryPreview() {
    loadDesignPreview()
    isBusy = false
    status = "Testing completed"
    plan = plan.map { item in
      var item = item
      item.state = .complete
      return item
    }
    if var journey = activeJourney {
      journey.status = .passed
      journey.steps = journey.steps.map { result in
        var result = result
        result.status = .passed
        result.detail = result.detail.isEmpty ? "Host check passed." : result.detail
        return result
      }
      activeJourney = journey
    }
    if let index = evidence.firstIndex(where: { $0.kind == .screenshot }) {
      evidence[index].status = .passed
      evidence[index].diagnosticSummary = "Synthetic fixture · final screen captured"
    }
    verificationReport = .init(
      status: .verified, currentEvidence: evidence, staleEvidence: [], missing: [])
    taskSummary = .init(
      title: "Testing completed",
      done: "Exercised 12 interactions for “Verify Profile appearance and navigation”.",
      worked:
        "App launch, 3 deterministic assertions, final screenshot, and terminal journey verification passed.",
      lacking: "No outstanding host checks.", passed: true)
    timeline.append(
      .init(
        time: "10:49", title: "Test summary",
        detail:
          "Done: Exercised the complete flow.\nWorked: Launch, assertions, screenshot, and terminal verification passed.\nStill missing: Nothing.",
        state: .complete))
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

  public func loadJourneyRecoveryPreview() {
    loadDesignPreview()
    isBusy = false
    status = "Testing · retry ready"
    guard var journey = activeJourney else { return }
    journey.status = .ready
    journey.steps = [
      .init(
        step: .init(
          id: "open-quiz", title: "Open Practice Quiz", actionID: "action_start",
          action: "tap", expectScreenChanged: true),
        status: .failed,
        detail: "That action is stale. Current app actions were refreshed."),
      .init(
        step: .init(
          id: "quiz-visible", title: "Quiz controls are visible",
          actionID: "action_answer_a", assertVisible: true),
        status: .waiting),
    ]
    activeJourney = journey
  }

  public func loadDesignBuildPreview() {
    loadDesignPreview()
    setCurrentScreenshot(nil)
    appOperation = .building
    isBusy = true
    status = "Building"
    timeline.append(
      .init(
        time: "10:49", title: "Build started", detail: "TravelApp · iPhone 16 Pro",
        state: .active))
  }

  public func loadPermissionPreview() {
    loadDesignPreview()
    status = "Awaiting permission"
    pendingAgentPermission = .init(
      toolCallID: "synthetic-command", title: "Run this command?",
      detail: "Codex wants to run the command below. Review it before continuing.",
      scopeLabel: "Isolated task",
      scopeDetail: "/Synthetic/Tasks/profile-dark-mode",
      command: "npm install @testing-library/react-native --save-dev",
      options: [
        .init(id: "allow-once", name: "Allow Once", kind: "allow_once"),
        .init(id: "allow-task", name: "Allow For This Session", kind: "allow_always"),
        .init(id: "reject-once", name: "Reject", kind: "reject_once"),
        .init(id: "reject-always", name: "Reject Always", kind: "reject_always"),
      ])
    timeline.append(
      .init(
        time: "10:48", title: "Install test dependency",
        detail: "Waiting for your approval", state: .active, category: .tool))
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

  public func showSnapshotPage(_ page: String) {
    switch page {
    case "code": section = .code
    case "changes": section = .changes
    case "deploy": section = .git
    case "settings": section = .settings
    default: section = .agent
    }
  }

  public func showSnapshotWorkspaceTab(_ tab: String) {
    isEvidenceWorkspaceOpen = true
    switch tab {
    case "terminal": evidenceWorkspaceTab = .terminal
    case "logs": evidenceWorkspaceTab = .logs
    default: evidenceWorkspaceTab = .evidence
    }
  }

  private func loadRepository(_ repository: URL, loadID: UUID) async {
    let git = URL(fileURLWithPath: "/usr/bin/git")
    let inside = try? await runner.run(
      executable: git, arguments: ["-C", repository.path, "rev-parse", "--is-inside-work-tree"])
    guard !Task.isCancelled, repositoryLoadID == loadID, self.repository == repository else {
      return
    }
    let gitRepository = inside?.succeeded == true
    var discoveredBranch = "read-only"
    if gitRepository,
      let branch = try? await runner.run(
        executable: git, arguments: ["-C", repository.path, "branch", "--show-current"])
    {
      let value = branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      discoveredBranch = value.isEmpty ? "detached" : value
    }
    guard !Task.isCancelled, repositoryLoadID == loadID, self.repository == repository else {
      return
    }
    isGitRepository = gitRepository
    branchName = discoveredBranch
    await refreshRepositoryChanges()
    await refreshProjectSelection()
    guard !Task.isCancelled, repositoryLoadID == loadID, self.repository == repository else {
      return
    }
    status =
      !gitRepository ? "Browse only" : needsExpoPreparation ? "Expo setup required" : "Ready"
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
      let workspace = repository ?? container.deletingLastPathComponent()
      let coordinator = WorkspaceOperationCoordinator(workspace: workspace)
      let lease = try await coordinator.acquire(.projectDiscovery)
      defer { lease.release() }
      guard FileManager.default.fileExists(atPath: container.path) else {
        throw RPCError(
          code: -32098,
          message: "The selected Xcode container no longer exists. Refresh the generated project before continuing."
        )
      }
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
      guard selectedContainer?.standardizedFileURL == container.standardizedFileURL else { return }
      schemes = ToolchainDiscovery.prioritizeSchemes(discoveredSchemes, for: container)
      if !schemes.contains(selectedScheme) { selectedScheme = schemes.first ?? "" }
    } catch {
      guard selectedContainer?.standardizedFileURL == container.standardizedFileURL else { return }
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
    adapter: DetectedAdapter, workspace: URL, prompt: String, intent: AgentTaskIntent,
    attachments: [ACPContentBlock] = []
  ) async throws -> Bool {
    guard let executable = adapter.executable else {
      throw RPCError(code: -32090, message: "The selected ACP adapter is unavailable")
    }
    let workspaceHandler = ACPWorkspaceRequestHandler(
      workspace: workspace, allowWrites: intent.allowsSourceWrites,
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
      params: try jsonValue(
        ACPInitialize(clientVersion: "0.1.0", allowWrites: intent.allowsSourceWrites)))
    guard initialized.result?["protocolVersion"]?.numberValue == Double(ACPProtocol.version) else {
      client.cancel()
      activeACPClient = nil
      throw RPCError(code: -32091, message: "The selected agent did not negotiate ACP v1")
    }
    let mcp = ACPMCPServer(
      name: "Lys Runtime", command: try mcpExecutable().path,
      env: try await runtime.mcpEnvironment().merging(
        ["LYS_INTENT_KIND": intent.kind.rawValue], uniquingKeysWith: { _, task in task }))
    let session = try await client.request(
      method: "session/new", params: try jsonValue(ACPNewSession(cwd: workspace, mcpServers: [mcp]))
    )
    guard let sessionID = session.result?["sessionId"]?.stringValue else {
      throw RPCError(code: -32092, message: "The ACP agent did not return a session ID")
    }
    updateAgentConfigOptions(
      session.result?["configOptions"] ?? session.result?["config_options"])
    activeACPSessionID = sessionID
    await applyPendingAgentConfigOptions(client: client, sessionID: sessionID)
    status = "Agent working"
    timeline.append(
      .init(
        time: Self.now(), title: "\(adapter.displayName) connected",
        detail: "ACP v1 session \(sessionID)", state: .complete))

    let context = agentContext(prompt: prompt, workspace: workspace, intent: intent)
    let result = try await client.request(
      method: "session/prompt",
      params: try jsonValue(
        ACPPrompt(sessionID: sessionID, content: [.init(text: context)] + attachments)))
    guard !agentStopRequested else { return false }
    let reason = result.result?["stopReason"]?.stringValue ?? "completed"
    finishAgentMessage()
    timeline.append(
      .init(
        time: Self.now(), title: "Agent response ended", detail: "Stop reason: \(reason)",
        state: intent.kind == .verifyCurrentApp ? .warning : .complete))
    return try await continueIncompleteTestingSession()
  }

  private func continueIncompleteTestingSession() async throws -> Bool {
    guard activeTaskIntent?.kind == .verifyCurrentApp, !agentStopRequested else { return false }
    guard let value = try? await runtime.request(method: "flow.status"),
      let journey: JourneyRecord = try? decodeRuntimeValue(value)
    else {
      throw RPCError(
        code: -32096,
        message: "The agent did not start the required host-owned app journey.")
    }
    if journey.status == .ready || journey.status == .running || journey.status == .preparing {
      activeJourney = journey
      return true
    }
    return false
  }

  private func finishIncompleteTestingSession() async {
    await refreshEvidence()
    await createTaskSummary()
    status = "Testing paused · continue the flow"
    timeline.append(
      .init(
        time: Self.now(), title: "Flow paused",
        detail: "The app remains attached. Continue the current journey to reach its terminal result.",
        state: .warning, category: .tool))
  }

  private func createTaskSummary(stopped: Bool = false) async {
    await refreshEvidence()
    if let value = try? await runtime.request(method: "flow.status"),
      let journey: JourneyRecord = try? decodeRuntimeValue(value)
    {
      activeJourney = journey
    }
    let currentEvidence = evidence.filter { $0.taskGeneration == generation }
    let actionCount = currentEvidence.filter { $0.kind == .uiAction && $0.status == .passed }.count
    let assertionCount = currentEvidence.filter {
      $0.kind == .uiAssertion && $0.status == .passed
    }.count
    let hasLaunch = currentEvidence.contains { $0.kind == .launch && $0.status == .passed }
    let hasScreenshot = currentEvidence.contains { $0.kind == .screenshot && $0.status == .passed }
    let verified: Bool
    if case .verified? = verificationReport?.status,
      activeTaskIntent?.kind != .verifyCurrentApp || activeJourney?.status == .passed
    {
      verified = true
    } else {
      verified = false
    }

    let done: String
    if stopped {
      done = "Stopped after \(actionCount) completed app interaction(s)."
    } else if let journey = activeJourney {
      switch journey.status {
      case .passed:
        done = "Completed “\(journey.goal)” with \(actionCount) app interaction(s)."
      case .failed:
        done =
          "Attempted “\(journey.goal)”; the flow did not complete. \(actionCount) interaction(s) passed before failure."
      case .cancelled:
        done = "Cancelled “\(journey.goal)” after \(actionCount) completed interaction(s)."
      case .preparing, .ready, .running:
        done =
          "Started “\(journey.goal)”, but it did not reach a terminal result. \(actionCount) interaction(s) passed."
      }
    } else {
      done = "Finished the requested task and collected the available evidence."
    }

    var workedParts: [String] = []
    if hasLaunch { workedParts.append("app launch") }
    if assertionCount > 0 { workedParts.append("\(assertionCount) deterministic assertion(s)") }
    if hasScreenshot { workedParts.append("final screenshot") }
    if activeJourney?.status == .passed { workedParts.append("terminal journey verification") }
    let worked =
      workedParts.isEmpty
      ? "No host-validated checks completed." : workedParts.joined(separator: ", ") + " passed."

    let lacking: String
    if stopped {
      lacking = "The remaining journey and final verification were not run."
    } else if let missing = verificationReport?.missing, !missing.isEmpty {
      lacking = missing.joined(separator: "; ") + "."
    } else if activeJourney?.status == .failed {
      lacking = "The journey ended with a failed host check; review the failed step above."
    } else {
      lacking = "No outstanding host checks."
    }

    taskSummary = .init(
      title: stopped
        ? "Testing stopped" : (verified ? "Testing completed" : "Testing needs attention"),
      done: done, worked: worked, lacking: lacking, passed: verified && !stopped)
    timeline.removeAll { $0.title == "Test summary" }
    timeline.append(
      .init(
        time: Self.now(), title: "Test summary",
        detail: "Done: \(done)\nWorked: \(worked)\nStill missing: \(lacking)",
        state: verified && !stopped ? .complete : .warning))
    if plan.indices.contains(3) {
      plan[3].state = verified && !stopped ? .complete : .blocked
    }
    if plan.indices.contains(4) {
      plan[4].state = verified && !stopped ? .complete : .blocked
    }
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
      consumeAgentMessageChunk(
        text,
        messageID: update["messageId"]?.stringValue
          ?? update["content"]?["messageId"]?.stringValue)
    case "tool_call", "tool_call_update":
      finishAgentMessage()
      consumeAgentToolUpdate(update)
    case "plan":
      finishAgentMessage()
      consumeAgentPlan(update)
    case "config_option_update":
      updateAgentConfigOptions(update["configOptions"] ?? update["config_options"])
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
    let toolCall = request.params?["toolCall"]
    let toolCallID = toolCall?["toolCallId"]?.stringValue
    let context = mergedToolContext(toolCall: toolCall, toolCallID: toolCallID)
    let fingerprint = permissionFingerprint(for: context)

    if let remembered = persistentPermissionChoices[fingerprint],
      options.contains(where: { $0.id == remembered })
    {
      return permissionResponse(id: request.id, optionID: remembered)
    }
    if isRoutineTestingTool(context),
      let option = options.first(where: { $0.kind == "allow_always" })
        ?? options.first(where: { $0.kind == "allow_once" })
    {
      if option.isPersistent { persistentPermissionChoices[fingerprint] = option.id }
      recordRoutineTestingPermissionIfNeeded()
      updateToolPermissionState(toolCallID: toolCallID, detail: "Approved for this task")
      return permissionResponse(id: request.id, optionID: option.id)
    }

    let presentation = permissionPresentation(for: context)
    updateToolPermissionState(toolCallID: toolCallID, detail: "Waiting for your approval")
    return await withCheckedContinuation { continuation in
      permissionContinuation = continuation
      pendingPermissionRPCID = request.id
      pendingPermissionFingerprint = fingerprint
      pendingAgentPermission = .init(
        toolCallID: toolCallID, title: presentation.title, detail: presentation.detail,
        scopeLabel: presentation.scopeLabel, scopeDetail: presentation.scopeDetail,
        command: presentation.command, options: options)
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
    let request = pendingAgentPermission
    if let optionID,
      let option = request?.options.first(where: { $0.id == optionID }), option.isPersistent,
      let fingerprint = pendingPermissionFingerprint
    {
      persistentPermissionChoices[fingerprint] = optionID
    }
    pendingPermissionRPCID = nil
    pendingPermissionFingerprint = nil
    pendingAgentPermission = nil
    status = "Agent working"
    if let request {
      let option = request.options.first(where: { $0.id == optionID })
      timeline.append(
        .init(
          time: Self.now(),
          title: option?.isAllow == true ? "Permission granted" : "Permission denied",
          detail: option?.displayName ?? "The action was cancelled",
          state: option?.isAllow == true ? .complete : .warning,
          category: .permission))
      updateToolPermissionState(
        toolCallID: request.toolCallID,
        detail: option?.isAllow == true ? "Approved" : "Denied")
    }
    continuation.resume(returning: permissionResponse(id: requestID, optionID: optionID))
  }

  private func consumeAgentMessageChunk(_ text: String, messageID: String?) {
    if let messageID, let current = agentMessageProtocolID, current != messageID {
      finishAgentMessage()
    }
    if agentMessageTimelineID == nil {
      agentMessageProtocolID = messageID
      timeline.append(
        .init(
          time: Self.now(), title: selectedAgentDisplayName, detail: "", state: .active,
          category: .agent))
      agentMessageTimelineID = timeline.last?.id
    }
    agentMessageBuffer += text
    guard agentMessageFlushTask == nil else { return }
    agentMessageFlushTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(75))
      guard !Task.isCancelled else { return }
      self?.flushAgentMessageBuffer()
    }
  }

  private func flushAgentMessageBuffer() {
    agentMessageFlushTask = nil
    guard !agentMessageBuffer.isEmpty, let id = agentMessageTimelineID,
      let index = timeline.firstIndex(where: { $0.id == id })
    else { return }
    timeline[index].detail += agentMessageBuffer
    agentMessageBuffer = ""
  }

  private func finishAgentMessage() {
    agentMessageFlushTask?.cancel()
    agentMessageFlushTask = nil
    flushAgentMessageBuffer()
    if let id = agentMessageTimelineID,
      let index = timeline.firstIndex(where: { $0.id == id })
    {
      timeline[index].state = .complete
    }
    agentMessageTimelineID = nil
    agentMessageProtocolID = nil
  }

  private func consumeAgentToolUpdate(_ update: JSONValue) {
    guard let toolCallID = update["toolCallId"]?.stringValue else { return }
    var context =
      agentToolContexts[toolCallID]
      ?? AgentToolContext(toolCallID: toolCallID)
    context.title = update["title"]?.stringValue ?? context.title
    context.name = update["name"]?.stringValue ?? context.name
    context.kind = update["kind"]?.stringValue ?? context.kind
    context.status = update["status"]?.stringValue ?? context.status
    context.rawInput = update["rawInput"] ?? context.rawInput
    context.rawOutput = update["rawOutput"] ?? context.rawOutput
    let newLocations = locationStrings(from: update["locations"])
    if !newLocations.isEmpty { context.locations = newLocations }
    agentToolContexts[toolCallID] = context

    let status = context.status ?? "in_progress"
    let state: TimelineItem.State =
      switch status {
      case "completed": .complete
      case "failed": .warning
      case "pending": .waiting
      default: .active
      }
    let detail = agentToolDetail(context, status: status)
    let title = humanizedToolTitle(context)
    if let timelineID = agentToolTimelineIDs[toolCallID],
      let index = timeline.firstIndex(where: { $0.id == timelineID })
    {
      timeline[index].title = title
      timeline[index].detail = detail
      timeline[index].state = state
    } else {
      timeline.append(
        .init(
          time: Self.now(), title: title, detail: detail, state: state, category: .tool))
      agentToolTimelineIDs[toolCallID] = timeline.last?.id
    }
  }

  private func consumeAgentPlan(_ update: JSONValue) {
    let entries = update["entries"]?.arrayValue ?? update["plan"]?["entries"]?.arrayValue ?? []
    guard !entries.isEmpty else { return }
    plan = entries.compactMap { entry in
      guard let title = entry["content"]?.stringValue ?? entry["title"]?.stringValue,
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return nil }
      let state: TaskPlanItem.State =
        switch entry["status"]?.stringValue {
        case "completed": .complete
        case "in_progress": .active
        case "blocked": .blocked
        default: .waiting
        }
      return .init(title: title, state: state)
    }
  }

  private func mergedToolContext(toolCall: JSONValue?, toolCallID: String?) -> AgentToolContext {
    let identifier = toolCallID ?? UUID().uuidString
    var context =
      agentToolContexts[identifier]
      ?? AgentToolContext(toolCallID: identifier)
    context.title = toolCall?["title"]?.stringValue ?? context.title
    context.name = toolCall?["name"]?.stringValue ?? context.name
    context.kind = toolCall?["kind"]?.stringValue ?? context.kind
    context.status = toolCall?["status"]?.stringValue ?? context.status
    context.rawInput = toolCall?["rawInput"] ?? context.rawInput
    context.rawOutput = toolCall?["rawOutput"] ?? context.rawOutput
    let locations = locationStrings(from: toolCall?["locations"])
    if !locations.isEmpty { context.locations = locations }
    if toolCallID != nil { agentToolContexts[identifier] = context }
    return context
  }

  private func permissionPresentation(for context: AgentToolContext) -> (
    title: String, detail: String, scopeLabel: String, scopeDetail: String?, command: String?
  ) {
    let command = commandText(from: context.rawInput)
    let workingDirectory =
      context.rawInput?["cwd"]?.stringValue
      ?? context.rawInput?["workingDirectory"]?.stringValue
    let firstLocation = context.locations.first
    let isInsideTask = [workingDirectory, firstLocation].compactMap { $0 }.contains {
      guard let taskWorkspace else { return false }
      let path = URL(fileURLWithPath: $0).standardizedFileURL.path
      let root = taskWorkspace.standardizedFileURL.path
      return path == root || path.hasPrefix(root + "/")
    }
    let scopeLabel =
      runtimeToolKey(context) != nil
      ? (selectedDestination?.name ?? "Selected Simulator")
      : isInsideTask ? "Isolated task" : context.kind == "fetch" ? "Network" : "Agent process"
    let scopeDetail = workingDirectory ?? firstLocation

    if let key = runtimeToolKey(context) {
      let action = Self.runtimeToolTitles[key] ?? humanizedToolTitle(context)
      if key == "app.reset_data" {
        return (
          "Reset the app's data?",
          "\(selectedAgentDisplayName) wants to erase this app's data on the selected Simulator. This cannot be undone.",
          scopeLabel, scopeDetail, nil
        )
      }
      return (
        "Allow app testing?",
        "\(selectedAgentDisplayName) wants to \(action.lowercased()) using Lys's iOS runtime.",
        scopeLabel, scopeDetail, nil
      )
    }

    switch context.kind {
    case "execute":
      return (
        "Run this command?",
        "\(selectedAgentDisplayName) wants to run the command below. Review it before continuing.",
        scopeLabel, scopeDetail, command
      )
    case "edit", "move":
      return (
        "Change files in this task?",
        "Changes stay in the isolated task worktree. Your original checkout is unchanged until review.",
        scopeLabel, scopeDetail, command
      )
    case "delete":
      return (
        "Delete files from this task?",
        "The agent wants to remove files from the isolated task. Review the affected location before continuing.",
        scopeLabel, scopeDetail, command
      )
    case "fetch":
      return (
        "Allow network access?",
        "\(selectedAgentDisplayName) wants to access an external resource.", scopeLabel,
        scopeDetail, command
      )
    default:
      let meaningful = [context.title, context.name]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty && !Self.looksLikeMachineToolName($0) }
      return (
        "Allow this agent action?", meaningful ?? "Review this action before continuing.",
        scopeLabel, scopeDetail, command
      )
    }
  }

  private func isRoutineTestingTool(_ context: AgentToolContext) -> Bool {
    guard let key = runtimeToolKey(context) else { return false }
    return Self.routineTestingTools.contains(key)
  }

  private func permissionFingerprint(for context: AgentToolContext) -> String {
    if let key = runtimeToolKey(context) { return "ios-runtime:\(key)" }
    return [context.kind ?? "other", commandText(from: context.rawInput) ?? "", context.name ?? ""]
      .joined(separator: ":")
  }

  private func permissionResponse(id: RPCID?, optionID: String?) -> RPCEnvelope {
    let outcome: JSONValue =
      optionID.map {
        .object(["outcome": .string("selected"), "optionId": .string($0)])
      } ?? .object(["outcome": .string("cancelled")])
    return .init(id: id, result: .object(["outcome": outcome]))
  }

  private func updateToolPermissionState(toolCallID: String?, detail: String) {
    guard let toolCallID, let timelineID = agentToolTimelineIDs[toolCallID],
      let index = timeline.firstIndex(where: { $0.id == timelineID })
    else { return }
    timeline[index].detail = detail
    timeline[index].state = detail == "Denied" ? .warning : .active
  }

  private func recordRoutineTestingPermissionIfNeeded() {
    guard !didRecordRoutineTestingPermission else { return }
    didRecordRoutineTestingPermission = true
    timeline.append(
      .init(
        time: Self.now(), title: "App testing access ready",
        detail:
          "Routine build, Simulator, UI, screenshot, and log tools are allowed for this task.",
        state: .complete, category: .permission))
  }

  private func resetAgentPresentation() {
    agentMessageFlushTask?.cancel()
    agentMessageFlushTask = nil
    agentMessageTimelineID = nil
    agentMessageProtocolID = nil
    agentMessageBuffer = ""
    agentToolContexts = [:]
    agentToolTimelineIDs = [:]
    agentConfigOptions = []
    pendingAgentConfigValues = [:]
    localAgentConfigOptions = Self.readLocalAgentConfigOptions(
      for: adapters.first(where: { $0.id == selectedAdapterID }))
    persistentPermissionChoices = [:]
    pendingPermissionFingerprint = nil
    didRecordRoutineTestingPermission = false
  }

  private func updateAgentConfigOptions(_ value: JSONValue?) {
    let values =
      value?.arrayValue
      ?? value?["configOptions"]?.arrayValue
      ?? value?["config_options"]?.arrayValue
    guard let values else {
      agentConfigOptions = []
      return
    }
    agentConfigOptions = values.compactMap { value in
      guard let data = try? JSONEncoder().encode(value) else { return nil }
      return try? JSONDecoder().decode(ACPConfigOption.self, from: data)
    }
  }

  private func isModelOption(_ option: ACPConfigOption) -> Bool {
    option.category?.lowercased() == "model"
      || option.id.localizedCaseInsensitiveContains("model")
      || option.name.localizedCaseInsensitiveContains("model")
  }

  private func isReasoningOption(_ option: ACPConfigOption) -> Bool {
    let category = option.category?.lowercased() ?? ""
    let id = option.id.lowercased()
    let name = option.name.lowercased()
    return category == "thought_level"
      || id.contains("reason") || id.contains("effort") || id.contains("thinking")
      || id.contains("thought") || name.contains("reason") || name.contains("effort")
      || name.contains("thinking") || name.contains("thought")
  }

  private func agentConfigKey(for option: ACPConfigOption) -> String? {
    if isModelOption(option) { return "model" }
    if isReasoningOption(option) { return "reasoning" }
    return nil
  }

  private func applyPendingAgentConfigOptions(client: ACPClient, sessionID: String) async {
    guard !pendingAgentConfigValues.isEmpty else { return }
    let pending = pendingAgentConfigValues
    pendingAgentConfigValues = [:]
    for (key, value) in pending {
      let option: ACPConfigOption?
      switch key {
      case "model": option = reportedAgentModelOption
      case "reasoning": option = reportedAgentReasoningOption
      default: option = nil
      }
      guard let option, option.options.contains(where: { $0.value == value }) else { continue }
      do {
        let result = try await client.request(
          method: "session/set_config_option",
          params: .object([
            "sessionId": .string(sessionID),
            "configId": .string(option.id),
            "value": .string(value),
          ]))
        updateAgentConfigOptions(
          result.result?["configOptions"] ?? result.result?["config_options"])
      } catch {
        notice = "Could not apply the saved \(key) setting: \(error.localizedDescription)"
      }
    }
  }

  private func agentConfigValueLabel(for option: ACPConfigOption?) -> String? {
    guard let option, let currentValue = option.currentValue else { return nil }
    switch currentValue {
    case .string(let value):
      return option.options.first(where: { $0.value == value })?.name ?? value
    case .bool(let value): return value ? "On" : "Off"
    case .number(let value): return String(value)
    case .object, .array, .null: return nil
    }
  }

  private var selectedAgentDisplayName: String {
    adapters.first(where: { $0.id == selectedAdapterID })?.displayName ?? "Agent"
  }

  private func humanizedToolTitle(_ context: AgentToolContext) -> String {
    if let key = runtimeToolKey(context), let title = Self.runtimeToolTitles[key] { return title }
    for value in [context.title, context.name].compactMap({ $0 }) {
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !clean.isEmpty && !Self.looksLikeMachineToolName(clean) { return clean }
    }
    return "Using a tool"
  }

  private func agentToolDetail(_ context: AgentToolContext, status: String) -> String {
    let locations = context.locations.map {
      URL(fileURLWithPath: $0).lastPathComponent.isEmpty
        ? $0 : URL(fileURLWithPath: $0).lastPathComponent
    }
    let locationDetail: String? = {
      guard !locations.isEmpty else { return nil }
      let visible = locations.prefix(3).joined(separator: ", ")
      let remaining = locations.count - min(locations.count, 3)
      return remaining > 0 ? "\(visible) +\(remaining)" : visible
    }()
    let commandDetail = commandText(from: context.rawInput).flatMap { command -> String? in
      let singleLine = command.split(whereSeparator: \.isNewline).joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !singleLine.isEmpty else { return nil }
      return singleLine.count > 104 ? "\(singleLine.prefix(101))…" : singleLine
    }

    switch status {
    case "completed":
      return locationDetail ?? commandDetail.map { "Completed · \($0)" } ?? "Completed"
    case "failed":
      return conciseToolFailure(context.rawOutput) ?? locationDetail.map { "Failed · \($0)" }
        ?? "Failed"
    case "pending":
      return locationDetail.map { "Waiting · \($0)" } ?? commandDetail.map { "Waiting · \($0)" }
        ?? "Waiting"
    default:
      if let locationDetail { return "Working on \(locationDetail)" }
      if let commandDetail { return "Running · \(commandDetail)" }
      if runtimeToolKey(context) != nil, let destination = selectedDestination?.name {
        return "Running on \(destination)"
      }
      return "In progress"
    }
  }

  private func runtimeToolKey(_ context: AgentToolContext) -> String? {
    let candidates = [context.title, context.name].compactMap { $0 }
    guard
      candidates.contains(where: {
        let value = $0.lowercased()
        return value.contains("ios_development_runtime")
          || value.contains("ios development runtime")
      })
    else { return nil }
    let combined = candidates.joined(separator: " ").lowercased()
    return Self.runtimeToolTitles.keys.first { combined.contains($0.lowercased()) }
  }

  private func commandText(from input: JSONValue?) -> String? {
    guard let command = input?["command"] else { return nil }
    if let string = command.stringValue { return string }
    if let arguments = command.arrayValue {
      return arguments.compactMap(\.stringValue).joined(separator: " ")
    }
    return renderJSON(command)
  }

  private func locationStrings(from value: JSONValue?) -> [String] {
    value?.arrayValue?.compactMap {
      $0["path"]?.stringValue ?? $0["uri"]?.stringValue ?? $0.stringValue
    } ?? []
  }

  private func conciseToolFailure(_ value: JSONValue?) -> String? {
    guard let value else { return nil }
    let text = toolFailureMessage(in: value) ?? renderJSON(value)
    let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    return line.count > 120 ? String(line.prefix(117)) + "…" : line
  }

  private func toolFailureMessage(in value: JSONValue, depth: Int = 0) -> String? {
    guard depth < 6 else { return nil }
    switch value {
    case .string(let text):
      if let data = text.data(using: .utf8),
        let nested = try? JSONDecoder().decode(JSONValue.self, from: data)
      {
        return toolFailureMessage(in: nested, depth: depth + 1)
      }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    case .object(let object):
      for key in ["message", "detail", "error_description", "text"] {
        if let nested = object[key], let message = toolFailureMessage(in: nested, depth: depth + 1)
        {
          return message
        }
      }
      for key in ["error", "structuredContent", "content", "result"] {
        guard let nested = object[key], nested != .null else { continue }
        if let message = toolFailureMessage(in: nested, depth: depth + 1) { return message }
      }
      return nil
    case .array(let values):
      for value in values {
        if let message = toolFailureMessage(in: value, depth: depth + 1) { return message }
      }
      return nil
    case .number, .bool, .null:
      return nil
    }
  }

  private func renderJSON(_ value: JSONValue) -> String {
    guard let data = try? JSONEncoder().encode(value),
      let text = String(data: data, encoding: .utf8)
    else { return "" }
    return text
  }

  private static func looksLikeMachineToolName(_ value: String) -> Bool {
    value.hasPrefix("mcp.") || value.hasPrefix("mcp__") || value.contains("_Runtime.")
      || value.contains("__Runtime__") || value.contains("tool_call")
  }

  private static let runtimeToolTitles: [String: String] = [
    "workspace.describe": "Inspecting the task workspace",
    "app.describe": "Mapping the current app",
    "flow.list": "Finding declared app flows",
    "flow.run": "Running the app flow",
    "flow.step": "Interacting with the app",
    "flow.finish": "Validating the completed flow",
    "flow.status": "Checking the app flow",
    "flow.stop": "Stopping the app flow",
    "build.run": "Building the app",
    "build.cancel": "Stopping the build",
    "test.list": "Finding tests",
    "test.run": "Running tests",
    "simulator.list": "Finding Simulators",
    "simulator.boot": "Starting the Simulator",
    "simulator.configure": "Configuring the Simulator",
    "devserver.start": "Starting the development server",
    "devserver.status": "Checking the development server",
    "devserver.stop": "Stopping the development server",
    "app.install_launch": "Installing and launching the app",
    "app.terminate": "Stopping the app",
    "app.reset_data": "Resetting app data",
    "ui.snapshot": "Inspecting the app",
    "ui.actions": "Reading available app actions",
    "ui.find": "Finding an interface element",
    "ui.perform": "Interacting with the app",
    "ui.wait": "Waiting for the app",
    "ui.assert": "Checking the interface",
    "ui.navigate": "Navigating the app",
    "screenshot.capture": "Capturing a screenshot",
    "logs.query": "Checking app logs",
    "evidence.summary": "Summarizing test evidence",
  ]

  private static let routineTestingTools: Set<String> = [
    "workspace.describe", "app.describe", "flow.list", "flow.run", "flow.step", "flow.finish",
    "flow.status", "flow.stop", "build.run", "test.list", "test.run", "screenshot.capture",
    "logs.query", "evidence.summary",
  ]

  private func startRuntime(workspace: URL) async throws {
    try await runtime.start(
      executable: try runtimeExecutable(), workspace: workspace, stateRoot: runtimeRoot,
      developerDirectory: developerDirectory)
    startRuntimeEventObserver()
  }

  private func ensureRuntimeForTask(workspace: URL) async throws {
    do {
      let description = try await runtime.request(method: "workspace.describe")
      if description["root"]?.stringValue != workspace.standardizedFileURL.path {
        try await startRuntime(workspace: workspace)
      } else {
        startRuntimeEventObserver()
      }
    } catch {
      try await startRuntime(workspace: workspace)
    }
  }

  private func configureRuntime(intent: AgentTaskIntent) async throws {
    let configuration = RuntimeSessionConfiguration(
      intent: intent, container: taskContainer()?.path, scheme: selectedScheme,
      destination: selectedDestination, target: selectedTarget,
      startDevelopmentServer: isExpoRepository && startDevServerOnRun)
    _ = try await runtime.request(
      method: "session.configure", params: try jsonValue(configuration))
  }

  private func startRuntimeEventObserver() {
    runtimeEventObserverTask?.cancel()
    runtimeEventSequence = 0
    runtimeEventObserverTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          let page = try await self.runtime.request(
            method: "runtime.events",
            params: .object(["after": .number(Double(self.runtimeEventSequence))]))
          let values: [RuntimeEvent] = try self.decodeRuntimeValue(
            page["events"] ?? .array([]))
          for event in values {
            self.runtimeEventSequence = max(self.runtimeEventSequence, event.sequence)
            await self.consumeRuntimeEvent(event)
          }
        } catch {
          if !Task.isCancelled { return }
        }
        try? await Task.sleep(for: .milliseconds(180))
      }
    }
  }

  private func decodeRuntimeValue<T: Decodable>(_ value: JSONValue) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
  }

  private func consumeRuntimeEvent(_ event: RuntimeEvent) async {
    if let target = event.target { selectedTarget = target }
    switch event.kind {
    case .sessionAttached, .appLaunched, .previewAvailable:
      if let destination = selectedDestination {
        if let target = event.target { selectedTarget = target }
        if selectedTarget != nil {
          warmPreviewInteraction(destination: destination, target: selectedTarget!)
          beginLiveSimulatorSession(destination: destination)
        }
      }
    case .screenshot:
      if let path = event.artifactPath {
        setCurrentScreenshot(URL(fileURLWithPath: path))
      }
      await refreshEvidence()
    case .journeyStarted, .journeyReady, .journeyStepStarted, .journeyStepFinished,
      .journeyFinished:
      if let value = try? await runtime.request(method: "flow.status"),
        let record: JourneyRecord = try? decodeRuntimeValue(value)
      {
        activeJourney = record
      }
      status = event.message
      if event.kind == .journeyFinished { await refreshEvidence() }
    case .assertion:
      await refreshEvidence()
    case .buildStarted:
      appOperation = .building
    case .buildFinished:
      appOperation = .idle
      await refreshEvidence()
    case .warning:
      status = "Testing needs another step"
      if timeline.last?.detail != event.message {
        timeline.append(
          .init(
            time: Self.now(), title: "Host testing note", detail: event.message,
            state: .warning))
      }
    case .sessionConfigured, .uiAction:
      break
    }
  }

  private func ensureRuntime() async throws {
    guard let workspace = taskWorkspace else { throw RuntimeControllerError.notRunning }
    do {
      let description = try await runtime.request(method: "workspace.describe")
      guard description["root"]?.stringValue == workspace.standardizedFileURL.path else {
        try await startRuntime(workspace: workspace)
        return
      }
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
    let buildArguments = [
      container.pathExtension == "xcworkspace" ? "-workspace" : "-project", container.path,
      "-scheme", selectedScheme, "-configuration", "Debug", "-destination",
      "platform=iOS Simulator,id=\(destination.udid)", "-derivedDataPath",
      taskWorkspace?.appending(path: ".lys/cache/DerivedData").path ?? "<derived-data>",
      "build",
    ]
    let terminalID = beginTerminal(
      executable: preflight?.xcodebuildPath ?? "xcodebuild", arguments: buildArguments,
      workingDirectory: taskWorkspace ?? container.deletingLastPathComponent())
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
      finishTerminal(
        terminalID, succeeded: passed,
        output: result["log"]?.stringValue ?? (passed ? "Build completed." : "Build failed."))
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
      finishTerminal(terminalID, succeeded: false, output: error.localizedDescription)
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
      // A build can take long enough for a development server to exit. Revalidate immediately
      // before installation so we never launch an Expo client against a dead port.
      if isExpoRepository && startDevServerOnRun { try await ensureMetro() }
      let booted = try await runtime.request(
        method: "simulator.boot", params: .object(["udid": .string(destination.udid)]))
      guard booted["succeeded"]?.boolValue == true else {
        throw RPCError(code: -32054, message: "The selected Simulator did not become ready")
      }
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
      let launched = try await runtime.request(
        method: "app.install_launch",
        params: .object([
          "udid": .string(destination.udid), "appPath": .string(productPath.path),
          "bundleID": .string(target.bundleID),
          "runtime": .string(destination.runtime),
          "startDevServer": .bool(false),
          "useDevServer": .bool(isExpoRepository && startDevServerOnRun),
        ]))
      guard launched["launched"]?.boolValue == true else {
        throw RPCError(code: -32053, message: "The selected app did not launch")
      }
      status = "Running"
      timeline.append(
        .init(
          time: Self.now(), title: "Application launched",
          detail: "\(target.bundleID) on \(destination.name)", state: .complete))
      warmPreviewInteraction(destination: destination, target: target)
      beginLiveSimulatorSession(destination: destination)
      status = "Waiting for app to settle"
      await captureScreenshot(settleDelayMS: isExpoRepository ? 2_500 : 900)
      let shouldVerifyMetro = isExpoRepository && startDevServerOnRun
      var metroStillReady = true
      if shouldVerifyMetro { metroStillReady = await isMetroReady() }
      if shouldVerifyMetro && !metroStillReady {
        timeline.append(
          .init(
            time: Self.now(), title: "Metro stopped during launch",
            detail: metroExitDiagnostic ?? "Restarting before presenting the app.",
            state: .warning))
        metroRecoveryTask?.cancel()
        metroRecoveryTask = nil
        try await ensureMetro()
        let retry = try await runtime.request(
          method: "app.install_launch",
          params: .object([
            "udid": .string(destination.udid), "appPath": .string(productPath.path),
            "bundleID": .string(target.bundleID),
            "runtime": .string(destination.runtime), "startDevServer": .bool(false),
            "useDevServer": .bool(true),
          ]))
        guard retry["launched"]?.boolValue == true else {
          throw RPCError(code: -32053, message: "The app did not relaunch after Metro restarted")
        }
        warmPreviewInteraction(destination: destination, target: target)
        beginLiveSimulatorSession(destination: destination)
        await captureScreenshot(settleDelayMS: 1_500)
      }
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

  @discardableResult
  private func captureScreenshot(settleDelayMS: Int = 0) async -> Bool {
    guard let destination = selectedDestination else { return false }
    do {
      let result = try await runtime.request(
        method: "screenshot.capture",
        params: .object([
          "udid": .string(destination.udid),
          "settleDelayMS": .number(Double(settleDelayMS)),
        ]))
      // The runtime returns the final artifact path. Present it immediately so
      // a manual capture is visible even before the evidence refresh completes.
      if let path = result["artifactPath"]?.stringValue {
        setCurrentScreenshot(URL(fileURLWithPath: path))
      }
      await refreshEvidence()
      return result["succeeded"]?.boolValue != false
    } catch {
      notice = error.localizedDescription
      return false
    }
  }

  private func refreshEvidence() async {
    do {
      evidence = try await runtime.request([Evidence].self, method: "evidence.list")
      setCurrentScreenshot(
        evidence.reversed().first(where: {
          $0.kind == .screenshot && $0.status == .passed && $0.taskGeneration == generation
        }).flatMap { $0.artifactPaths.first.map(URL.init(fileURLWithPath:)) })
      var report: VerificationReport = try await runtime.request(
        VerificationReport.self, method: "verification.status",
        params: .object([
          "codeChanged": .bool(
            activeWorktree != nil || evidence.contains(where: { $0.kind == .build })),
          "uiChanged": .bool(requiresUIVerification),
          "testsChanged": .bool(false),
        ]))
      if activeTaskIntent?.kind == .verifyCurrentApp, activeJourney?.status != .passed {
        report.status = activeJourney?.status == .failed ? .failed : .partiallyVerified
        if !report.missing.contains("A declared Lys flow reaching its terminal state") {
          report.missing.append("A declared Lys flow reaching its terminal state")
        }
      }
      verificationReport = report
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
    proposedChangesRevision += 1
  }

  func discoverAppStoreDistributionTarget() async throws -> AppTarget {
    guard let container = taskContainer(), !selectedScheme.isEmpty else {
      throw RPCError(
        code: -32056,
        message: "Select an Xcode project or workspace and a shared app scheme first.")
    }
    let resolvedPreflight: ToolchainPreflight
    if let preflight {
      resolvedPreflight = preflight
    } else {
      resolvedPreflight = await ToolchainDiscovery.preflight(
        developerDirectory: developerDirectory)
    }
    guard let xcodebuildPath = resolvedPreflight.xcodebuildPath,
      let developerPath = resolvedPreflight.developerDirectory
    else {
      throw RPCError(
        code: -32050,
        message: "Select a full Xcode installation in Settings to verify the Release bundle ID.")
    }
    let workspace = taskWorkspace ?? repository ?? container.deletingLastPathComponent()
    let coordinator = WorkspaceOperationCoordinator(workspace: workspace)
    let lease = try await coordinator.acquire(.projectDiscovery)
    defer { lease.release() }
    let derivedData = runtimeRoot.appending(
      path: "DeploymentDiscovery", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: derivedData, withIntermediateDirectories: true)
    let targets = try await ToolchainDiscovery.appTargets(
      container: container, scheme: selectedScheme, configuration: "Release",
      destination: "generic/platform=iOS", xcodebuild: URL(fileURLWithPath: xcodebuildPath),
      developerDirectory: URL(fileURLWithPath: developerPath), derivedData: derivedData)
    guard let target = targets.first else {
      throw RPCError(
        code: -32056,
        message:
          "The \(selectedScheme) scheme does not expose an iOS app target for the Release configuration."
      )
    }
    return target
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
      executableDirectory?.appending(path: "lysd"),
      Bundle.main.resourceURL?.appending(path: "bin/lysd"),
    ].compactMap { $0 }
    if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) {
      return match
    }
    throw RuntimeControllerError.executableMissing(candidates.first?.path ?? "lysd")
  }

  private func mcpExecutable() throws -> URL {
    let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
    let candidates = [
      executableDirectory?.appending(path: "lys-mcp"),
      Bundle.main.resourceURL?.appending(path: "bin/lys-mcp"),
    ].compactMap { $0 }
    if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) {
      return match
    }
    throw RuntimeControllerError.executableMissing(candidates.first?.path ?? "lys-mcp")
  }

  private func npmExecutable() -> URL? {
    ["/opt/homebrew/bin/npm", "/usr/local/bin/npm", "/usr/bin/npm"]
      .map(URL.init(fileURLWithPath:))
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  private func podExecutable() -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      URL(fileURLWithPath: "/opt/homebrew/bin/pod"),
      URL(fileURLWithPath: "/usr/local/bin/pod"),
      home.appending(path: ".rbenv/shims/pod"),
      home.appending(path: ".asdf/shims/pod"),
    ].first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  private var requiredCocoaPodsInstall: CocoaPodsRequirement? {
    taskContainer().flatMap(CocoaPodsSupport.missingInstallation(for:))
  }

  private func approveRequiredCocoaPodsInstall() -> Bool {
    guard let requirement = requiredCocoaPodsInstall else { return true }
    let command = "pod \(requirement.installArguments.joined(separator: " "))"
    let confirmation = NSAlert()
    confirmation.messageText = "Install CocoaPods dependencies?"
    confirmation.informativeText =
      "The selected app cannot build because \(requirement.reason) Lys will run `\(command)` in \(requirement.projectDirectory.path). This executes the Podfile and may access the network."
    confirmation.addButton(withTitle: "Install Pods and Continue")
    confirmation.addButton(withTitle: "Cancel")
    return confirmation.runModal() == .alertFirstButtonReturn
  }

  private func installRequiredCocoaPods() async throws {
    guard let requirement = requiredCocoaPodsInstall else { return }
    guard let pod = podExecutable() else {
      throw RPCError(
        code: -32059,
        message:
          "CocoaPods is required for this project but `pod` was not found. Install CocoaPods, then Run again."
      )
    }

    let workspace = taskWorkspace ?? repository ?? requirement.projectDirectory
    let coordinator = WorkspaceOperationCoordinator(workspace: workspace)
    let lease = try await coordinator.acquire(.cocoaPodsInstall)
    defer { lease.release() }

    status = "Installing CocoaPods dependencies"
    appOperation = .preparing
    timeline.append(
      .init(
        time: Self.now(), title: "Installing CocoaPods dependencies",
        detail: requirement.projectDirectory.path, state: .active))
    var environment = [
      "PATH": executableSearchPath(),
      "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
    ]
    if let locale = ProcessInfo.processInfo.environment["LC_ALL"] {
      environment["LC_ALL"] = locale
    }

    var outcome = try await runCocoaPods(
      executable: pod, arguments: requirement.installArguments,
      directory: requirement.projectDirectory, environment: environment)
    var detail = (outcome.stderr + outcome.stdout).trimmingCharacters(
      in: .whitespacesAndNewlines)
    if !outcome.succeeded, requirement.installArguments.contains("--deployment"),
      detail.contains("changes to the lockfile")
    {
      guard approveCocoaPodsLockfileUpdate(in: requirement.projectDirectory) else {
        throw RPCError(
          code: -32059,
          message:
            "Podfile.lock is out of date. Update it with `pod install`, review the resulting Git diff, then Run again."
        )
      }
      outcome = try await runCocoaPods(
        executable: pod, arguments: ["install"], directory: requirement.projectDirectory,
        environment: environment)
      detail = (outcome.stderr + outcome.stdout).trimmingCharacters(
        in: .whitespacesAndNewlines)
    }
    guard outcome.succeeded else {
      throw RPCError(
        code: -32059, message: "CocoaPods installation failed",
        data: .string(detail.isEmpty ? "See the Terminal transcript." : detail))
    }
    if let remaining = CocoaPodsSupport.missingInstallation(in: requirement.projectDirectory) {
      throw RPCError(
        code: -32059,
        message: "CocoaPods finished, but the installation is incomplete: \(remaining.reason)")
    }
    timeline.append(
      .init(
        time: Self.now(), title: "CocoaPods dependencies ready",
        detail:
          "Installed the locked dependencies for \(requirement.projectDirectory.lastPathComponent).",
        state: .complete))
  }

  private func approveCocoaPodsLockfileUpdate(in directory: URL) -> Bool {
    let confirmation = NSAlert()
    confirmation.messageText = "Update Podfile.lock?"
    confirmation.informativeText =
      "CocoaPods refused the locked installation because the Podfile or CocoaPods version changed. Lys can run `pod install` in \(directory.path). This may modify the tracked Podfile.lock and generated support files; review the Git diff afterward."
    confirmation.addButton(withTitle: "Update Lockfile and Continue")
    confirmation.addButton(withTitle: "Cancel")
    return confirmation.runModal() == .alertFirstButtonReturn
  }

  private func runCocoaPods(
    executable: URL, arguments: [String], directory: URL, environment: [String: String]
  ) async throws -> ProcessOutcome {
    let terminalID = beginTerminal(
      executable: executable.path, arguments: arguments, workingDirectory: directory)
    do {
      let outcome = try await runner.run(
        executable: executable, arguments: arguments, workingDirectory: directory,
        environment: environment, maximumOutputBytes: 32 * 1_024 * 1_024,
        onEvent: { [weak self] event in
          guard event.stream != .lifecycle else { return }
          Task { @MainActor [weak self] in
            self?.appendTerminalOutput(terminalID, text: event.text)
          }
        })
      finishTerminal(terminalID, succeeded: outcome.succeeded, output: "", append: true)
      return outcome
    } catch {
      finishTerminal(terminalID, succeeded: false, output: error.localizedDescription, append: true)
      throw error
    }
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
      "This project includes generated fmt or MMKV sources that Apple Clang 21 cannot compile. Lys will apply narrow repairs inside ios/Pods only. Regenerating ios/Pods removes them."
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
    guard let workspace = expoProjectRoot, let npm = npmExecutable() else {
      throw RPCError(
        code: -32096,
        message: "npm was not found. Install Node.js, then reopen Lys.")
    }

    if metroTask != nil, metroWorkspace?.standardizedFileURL != workspace.standardizedFileURL {
      await stopOwnedMetro()
    }
    if metroTask != nil, let previousExit = metroExitDiagnostic {
      cancelOwnedMetro()
      timeline.append(
        .init(
          time: Self.now(), title: "Restarting Metro",
          detail: previousExit, state: .warning))
    }
    if await isMetroReady() {
      if metroTask == nil {
        let owner = await metroOwnerWorkspace()
        guard owner?.standardizedFileURL == workspace.standardizedFileURL else {
          throw RPCError(
            code: -32099,
            message:
              "Port 8081 is serving a different project\(owner.map { " at \($0.path)" } ?? ""). Stop that Metro server, then Run again."
          )
        }
      }
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
      let terminalID = beginTerminal(
        executable: npm.path, arguments: ["start", "--", "--port", "8081"],
        workingDirectory: workspace)
      metroTerminalID = terminalID
      let searchPath = executableSearchPath()
      let task = Task.detached { [metroRunner] in
        try await metroRunner.run(
          executable: npm, arguments: ["start", "--", "--port", "8081"],
          workingDirectory: workspace,
          environment: DevelopmentServerEnvironment.local(searchPath: searchPath),
          maximumOutputBytes: 8 * 1_024 * 1_024,
          onEvent: { [weak self] event in
            guard event.stream != .lifecycle else { return }
            Task { @MainActor [weak self] in
              self?.appendTerminalOutput(terminalID, text: event.text)
            }
          })
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
          self.finishTerminal(terminalID, succeeded: outcome.succeeded, output: "", append: true)
        case .failure(let error):
          self.metroExitDiagnostic = error.localizedDescription
          self.finishTerminal(
            terminalID, succeeded: false, output: error.localizedDescription, append: true)
        }
        self.scheduleMetroRecovery(afterExitFrom: workspace, runID: runID)
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

  private func metroOwnerWorkspace() async -> URL? {
    let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")
    guard FileManager.default.isExecutableFile(atPath: lsof.path),
      let listener = try? await runner.run(
        executable: lsof,
        arguments: ["-nP", "-tiTCP:8081", "-sTCP:LISTEN"],
        maximumOutputBytes: 64 * 1_024),
      let pid = listener.stdout.split(whereSeparator: \.isNewline).first
    else { return nil }
    guard
      let details = try? await runner.run(
        executable: lsof, arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"],
        maximumOutputBytes: 64 * 1_024)
    else { return nil }
    guard
      let path = details.stdout.split(whereSeparator: \.isNewline)
        .map(String.init).first(where: { $0.hasPrefix("n/") })
    else { return nil }
    return URL(fileURLWithPath: String(path.dropFirst()))
  }

  private func cancelOwnedMetro() {
    metroRunID = nil
    metroWorkspace = nil
    metroExitDiagnostic = nil
    if let metroTerminalID,
      let index = terminalEntries.firstIndex(where: { $0.id == metroTerminalID }),
      terminalEntries[index].state == .running
    {
      terminalEntries[index].state = .cancelled
    }
    metroTerminalID = nil
    metroTask?.cancel()
    metroTask = nil
  }

  private func disableMetroPersistence() {
    metroShouldStayRunning = false
    metroRecoveryTask?.cancel()
    metroRecoveryTask = nil
  }

  private func scheduleMetroRecovery(afterExitFrom workspace: URL, runID: UUID) {
    guard metroShouldStayRunning, metroRunID == runID, metroRecoveryTask == nil else { return }
    metroRecoveryTask = Task { [weak self] in
      guard let self else { return }
      defer { self.metroRecoveryTask = nil }
      try? await Task.sleep(for: .milliseconds(600))
      while self.isBusy && !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
      }
      guard !Task.isCancelled, self.metroShouldStayRunning,
        self.expoProjectRoot?.standardizedFileURL == workspace.standardizedFileURL
      else {
        return
      }
      self.timeline.append(
        .init(
          time: Self.now(), title: "Metro stopped unexpectedly",
          detail: self.metroExitDiagnostic ?? "Restarting the development server.",
          state: .warning))
      do {
        try await self.ensureMetro()
        guard self.metroShouldStayRunning else { return }
        try await self.relaunchAfterMetroRecovery()
        self.status = "Running · Metro recovered"
        self.timeline.append(
          .init(
            time: Self.now(), title: "Metro recovered",
            detail: "The development server restarted and the app was relaunched.",
            state: .complete))
      } catch {
        self.status = "Metro stopped"
        self.notice =
          "The development server stopped and could not be restarted. \(error.localizedDescription)"
      }
    }
  }

  private func relaunchAfterMetroRecovery() async throws {
    guard let destination = selectedDestination, let target = selectedTarget,
      let productPath = target.productPath
    else { return }
    try await ensureRuntime()
    let relaunched = try await runtime.request(
      method: "app.install_launch",
      params: .object([
        "udid": .string(destination.udid), "appPath": .string(productPath.path),
        "bundleID": .string(target.bundleID), "startDevServer": .bool(false),
        "useDevServer": .bool(true),
      ]))
    guard relaunched["launched"]?.boolValue == true else {
      throw RPCError(code: -32053, message: "The app did not relaunch after Metro restarted")
    }
    await captureScreenshot(settleDelayMS: 1_500)
    warmPreviewInteraction(destination: destination, target: target)
    beginLiveSimulatorSession(destination: destination)
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

  @discardableResult private func beginTerminal(
    executable: String, arguments: [String], workingDirectory: URL
  ) -> UUID {
    let command = ([executable] + arguments).map(Self.displayArgument).joined(separator: " ")
    let entry = TerminalEntry(command: command, workingDirectory: workingDirectory.path)
    terminalEntries.append(entry)
    if terminalEntries.count > 40 { terminalEntries.removeFirst(terminalEntries.count - 40) }
    return entry.id
  }

  private func appendTerminalOutput(_ id: UUID, text: String) {
    guard terminalEntries.contains(where: { $0.id == id }), !text.isEmpty else { return }
    terminalOutputBuffers[id, default: ""].append(text)
    scheduleTerminalFlush()
  }

  private func finishTerminal(
    _ id: UUID, succeeded: Bool, output: String, append: Bool = false
  ) {
    flushTerminalOutput(id: id)
    guard let index = terminalEntries.firstIndex(where: { $0.id == id }) else { return }
    if append {
      appendTerminalOutputImmediately(id: id, text: output)
    } else {
      terminalEntries[index].output = output
    }
    terminalEntries[index].state = succeeded ? .succeeded : .failed
    if !succeeded { isEvidenceWorkspaceOpen = true }
  }

  private func scheduleTerminalFlush() {
    guard terminalFlushTask == nil else { return }
    terminalFlushTask = Task {
      try? await Task.sleep(for: .milliseconds(80))
      guard !Task.isCancelled else { return }
      flushTerminalOutput()
      terminalFlushTask = nil
      if !terminalOutputBuffers.isEmpty { scheduleTerminalFlush() }
    }
  }

  private func flushTerminalOutput(id: UUID? = nil) {
    let pending: [UUID: String]
    if let id {
      guard let text = terminalOutputBuffers.removeValue(forKey: id) else { return }
      pending = [id: text]
    } else {
      pending = terminalOutputBuffers
      terminalOutputBuffers = [:]
    }
    guard !pending.isEmpty else { return }
    var updated = terminalEntries
    for (entryID, text) in pending {
      guard let index = updated.firstIndex(where: { $0.id == entryID }) else { continue }
      updated[index].output.append(text)
      truncateTerminalOutput(&updated[index].output)
    }
    terminalEntries = updated
  }

  private func appendTerminalOutputImmediately(id: UUID, text: String) {
    guard !text.isEmpty, let index = terminalEntries.firstIndex(where: { $0.id == id }) else {
      return
    }
    terminalEntries[index].output.append(text)
    truncateTerminalOutput(&terminalEntries[index].output)
  }

  private func truncateTerminalOutput(_ output: inout String) {
    let limit = 1_000_000
    if output.utf8.count > limit {
      output = "[earlier output truncated]\n" + String(output.suffix(limit))
    }
  }

  var appStoreDeploymentArtifactsRoot: URL { deploymentRoot }

  func appStoreDeploymentContainer() -> URL? { taskContainer() }

  func runAppStoreDistributionCommand(
    _ command: CommandSpec, credentialPath: String? = nil
  ) async throws -> ProcessOutcome {
    let displayedArguments = redactedDistributionArguments(
      command.arguments, credentialPath: credentialPath)
    let terminalID = beginTerminal(
      executable: command.executable.path, arguments: displayedArguments,
      workingDirectory: taskWorkspace ?? command.executable.deletingLastPathComponent())
    do {
      let outcome = try await appStoreDistributionRunner.run(
        executable: command.executable, arguments: command.arguments,
        workingDirectory: taskWorkspace, environment: command.environment,
        maximumOutputBytes: 16 * 1_024 * 1_024
      ) { [weak self] event in
        guard event.stream != .lifecycle else { return }
        let output = credentialPath.map {
          event.text.replacingOccurrences(of: $0, with: "[secure temporary key]")
        } ?? event.text
        Task { @MainActor [weak self] in
          self?.appendTerminalOutput(terminalID, text: output)
        }
      }
      finishTerminal(terminalID, succeeded: outcome.succeeded, output: "", append: true)
      return outcome
    } catch {
      finishTerminal(
        terminalID, succeeded: false, output: "\n\(error.localizedDescription)\n", append: true)
      throw error
    }
  }

  func cancelAppStoreDistributionCommands() async {
    await appStoreDistributionRunner.cancelAll()
  }

  private func redactedDistributionArguments(
    _ arguments: [String], credentialPath: String?
  ) -> [String] {
    guard let credentialPath else { return arguments }
    return arguments.map {
      $0 == credentialPath ? "[secure temporary key]" : $0
    }
  }

  private func setCurrentScreenshot(_ url: URL?) {
    currentScreenshot = url
    guard let url else {
      currentScreenshotImage = nil
      return
    }
    let image = NSImage(contentsOf: url)
    image?.cacheMode = .always
    currentScreenshotImage = image
  }

  private static func readLocalAgentConfigOptions(for adapter: DetectedAdapter?)
    -> [ACPConfigOption]
  {
    guard let adapter,
      let lockEntry = AdapterManager.pinned.first(where: { $0.id == adapter.id })
    else { return [] }
    let home = FileManager.default.homeDirectoryForCurrentUser
    var files: [URL] = []
    let knownNames = [
      "config.toml", "settings.json", "config.json", "opencode.json", "preferences.json",
      "models_cache.json",
    ]
    for path in lockEntry.configurationPaths {
      let root = home.appending(path: path)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
        continue
      }
      if isDirectory.boolValue {
        files.append(contentsOf: knownNames.map { root.appending(path: $0) })
      } else {
        files.append(root)
      }
    }
    files = files.filter { FileManager.default.isReadableFile(atPath: $0.path) }

    var model: String?
    var reasoning: String?
    for file in files where file.lastPathComponent != "models_cache.json" {
      let values = localConfigValues(at: file)
      model = model ?? values.model
      reasoning = reasoning ?? values.reasoning
    }

    let modelValues: [ACPConfigOptionValue]
    let reasoningValues: [ACPConfigOptionValue]
    if adapter.id == "codex" {
      let cache = home.appending(path: ".codex/models_cache.json")
      modelValues = codexModelValues(at: cache, selected: model)
      reasoningValues = codexReasoningValues(at: cache, selectedModel: model)
    } else {
      modelValues = model.map { [.init(value: $0, name: $0)] } ?? []
      reasoningValues = reasoning.map { [.init(value: $0, name: $0)] } ?? []
    }

    var options: [ACPConfigOption] = []
    if let model {
      options.append(
        .init(
          id: "local-model", name: "Model", category: "model",
          currentValue: .string(model),
          options: modelValues.isEmpty
            ? [.init(value: model, name: model)] : modelValues))
    }
    if let reasoning {
      options.append(
        .init(
          id: "local-reasoning", name: "Reasoning effort", category: "thought_level",
          currentValue: .string(reasoning),
          options: reasoningValues.isEmpty
            ? [.init(value: reasoning, name: reasoning.capitalized)] : reasoningValues))
    }
    return options
  }

  private static func localConfigValues(at url: URL) -> (model: String?, reasoning: String?) {
    guard let data = try? Data(contentsOf: url), data.count <= 4_000_000 else {
      return (nil, nil)
    }
    if url.pathExtension.lowercased() == "toml" {
      return tomlConfigValues(String(decoding: data, as: UTF8.self))
    }
    guard let object = try? JSONSerialization.jsonObject(with: data) else { return (nil, nil) }
    var model: String?
    var reasoning: String?
    collectConfigValues(from: object, model: &model, reasoning: &reasoning)
    return (model, reasoning)
  }

  private static func tomlConfigValues(_ text: String) -> (model: String?, reasoning: String?) {
    let modelKeys = ["model", "model_id", "model_name", "default_model", "selected_model"]
    let reasoningKeys = [
      "model_reasoning_effort", "reasoning_effort", "reasoning", "thinking_level",
      "thought_level",
    ]
    var model: String?
    var reasoning: String?
    for rawLine in text.split(whereSeparator: \.isNewline) {
      let line = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
      let parts = line.split(separator: "=", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      }
      guard parts.count == 2 else { continue }
      let key = parts[0].replacingOccurrences(of: "-", with: "_")
      var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
      if value.hasPrefix("\"") && value.hasSuffix("\"") {
        value.removeFirst()
        value.removeLast()
      } else if value.hasPrefix("'") && value.hasSuffix("'") {
        value.removeFirst()
        value.removeLast()
      }
      guard !value.isEmpty else { continue }
      if model == nil && modelKeys.contains(key) { model = value }
      if reasoning == nil && reasoningKeys.contains(key) { reasoning = value }
    }
    return (model, reasoning)
  }

  private static func collectConfigValues(
    from value: Any, model: inout String?, reasoning: inout String?
  ) {
    guard model == nil || reasoning == nil else { return }
    if let object = value as? [String: Any] {
      for (key, child) in object {
        let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
        if model == nil
          && ["model", "model_id", "model_name", "default_model"].contains(normalized),
          let string = child as? String, !string.isEmpty
        {
          model = string
        }
        if reasoning == nil
          && [
            "model_reasoning_effort", "reasoning_effort", "reasoning", "thinking_level",
            "thought_level",
          ].contains(normalized),
          let string = child as? String, !string.isEmpty
        {
          reasoning = string
        }
        collectConfigValues(from: child, model: &model, reasoning: &reasoning)
      }
    } else if let array = value as? [Any] {
      for child in array {
        collectConfigValues(from: child, model: &model, reasoning: &reasoning)
      }
    }
  }

  private static func codexModelValues(at url: URL, selected: String?)
    -> [ACPConfigOptionValue]
  {
    guard let data = try? Data(contentsOf: url), data.count <= 20_000_000,
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let models = root["models"] as? [[String: Any]]
    else { return selected.map { [.init(value: $0, name: $0)] } ?? [] }

    var values: [ACPConfigOptionValue] = []
    for model in models {
      guard let slug = model["slug"] as? String, !slug.isEmpty else { continue }
      let name =
        (model["display_name"] as? String).flatMap {
          $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        } ?? slug
      values.append(
        .init(value: slug, name: name, description: model["description"] as? String))
    }
    let unique = Dictionary(values.map { ($0.value, $0) }, uniquingKeysWith: { first, _ in first })
      .values
    return unique.sorted {
      if $0.value == selected { return true }
      if $1.value == selected { return false }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }.prefix(24).map { $0 }
  }

  private static func codexReasoningValues(at url: URL, selectedModel: String?)
    -> [ACPConfigOptionValue]
  {
    guard let data = try? Data(contentsOf: url), data.count <= 20_000_000,
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let models = root["models"] as? [[String: Any]]
    else { return [] }
    let model = models.first(where: { $0["slug"] as? String == selectedModel }) ?? models.first
    guard let levels = model?["supported_reasoning_levels"] as? [[String: Any]] else { return [] }
    return levels.compactMap { level in
      guard let effort = level["effort"] as? String, !effort.isEmpty else { return nil }
      return .init(
        value: effort, name: effort.capitalized, description: level["description"] as? String)
    }
  }

  private static func displayArgument(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/:=,"))
    if value.unicodeScalars.allSatisfy(safe.contains) { return value }
    return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }

  private static func children(of url: URL) -> [FileNode] {
    (try? FileTreeLoader.contents(of: url)) ?? []
  }

  private static func packageUsesExpo(at directory: URL) -> Bool {
    guard let data = try? Data(contentsOf: directory.appending(path: "package.json")),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    let dependencies = root["dependencies"] as? [String: Any]
    let development = root["devDependencies"] as? [String: Any]
    return dependencies?["expo"] != nil || development?["expo"] != nil
  }

  private static func now() -> String {
    Date().formatted(date: .omitted, time: .shortened)
  }
}
