import Foundation

public enum AgentTaskKind: String, Codable, CaseIterable, Equatable, Sendable {
  case verifyCurrentApp
  case modifyAndVerify
  case runTests
  case inspectCurrentApp
}

public enum AgentWorkspacePolicy: String, Codable, Equatable, Sendable {
  case currentCheckout
  case isolatedWorktree
}

public enum AgentBuildPolicy: String, Codable, Equatable, Sendable {
  case never
  case ifMissing
  case ifStale
}

public enum AgentAppStatePolicy: String, Codable, Equatable, Sendable {
  case preserve
  case relaunch
}

public struct AgentTaskIntent: Codable, Equatable, Sendable {
  public var kind: AgentTaskKind
  public var workspacePolicy: AgentWorkspacePolicy
  public var buildPolicy: AgentBuildPolicy
  public var appStatePolicy: AgentAppStatePolicy
  public var allowsSourceWrites: Bool
  public var requiresRunningApp: Bool

  public init(
    kind: AgentTaskKind, workspacePolicy: AgentWorkspacePolicy, buildPolicy: AgentBuildPolicy,
    appStatePolicy: AgentAppStatePolicy, allowsSourceWrites: Bool, requiresRunningApp: Bool
  ) {
    self.kind = kind
    self.workspacePolicy = workspacePolicy
    self.buildPolicy = buildPolicy
    self.appStatePolicy = appStatePolicy
    self.allowsSourceWrites = allowsSourceWrites
    self.requiresRunningApp = requiresRunningApp
  }
}

public enum AgentTaskIntentRouter {
  public static func classify(_ prompt: String) -> AgentTaskIntent {
    let text = prompt.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
    let mutationTerms = [
      "add ", "build ", "change ", "create ", "delete ", "design ", "edit ", "fix ",
      "implement ", "improve ", "make ", "modify ", "refactor ", "remove ", "rename ",
      "replace ", "update ", "write ",
    ]
    let asksForMutation = mutationTerms.contains { text.contains($0) }
    if asksForMutation {
      return .init(
        kind: .modifyAndVerify, workspacePolicy: .isolatedWorktree, buildPolicy: .ifStale,
        appStatePolicy: .relaunch, allowsSourceWrites: true, requiresRunningApp: true)
    }

    let sourceTestTerms = ["unit test", "test suite", "xctest", "swift test", "run tests"]
    if sourceTestTerms.contains(where: text.contains) && !text.contains("ui test") {
      return .init(
        kind: .runTests, workspacePolicy: .currentCheckout, buildPolicy: .never,
        appStatePolicy: .preserve, allowsSourceWrites: false, requiresRunningApp: false)
    }

    let inspectTerms = ["inspect", "look at", "show me", "screenshot", "what is on", "explore"]
    if inspectTerms.contains(where: text.contains) && !text.contains("test")
      && !text.contains("verify")
    {
      return .init(
        kind: .inspectCurrentApp, workspacePolicy: .currentCheckout, buildPolicy: .ifMissing,
        appStatePolicy: .preserve, allowsSourceWrites: false, requiresRunningApp: true)
    }

    let verifyTerms = [
      "check", "exercise", "test", "try", "validate", "verification", "verify", "walk through",
    ]
    if verifyTerms.contains(where: text.contains) {
      return .init(
        kind: .verifyCurrentApp, workspacePolicy: .currentCheckout, buildPolicy: .ifMissing,
        appStatePolicy: .preserve, allowsSourceWrites: false, requiresRunningApp: true)
    }

    // Ambiguous requests never receive source-write or lifecycle authority. The agent can inspect
    // context and ask a follow-up; explicit mutation language is required to create a worktree.
    return .init(
      kind: .inspectCurrentApp, workspacePolicy: .currentCheckout, buildPolicy: .ifMissing,
      appStatePolicy: .preserve, allowsSourceWrites: false, requiresRunningApp: true)
  }
}

public struct RuntimeSessionConfiguration: Codable, Sendable {
  public var intent: AgentTaskIntent
  public var container: String?
  public var scheme: String
  public var configuration: String
  public var destination: Destination?
  public var target: AppTarget?
  public var startDevelopmentServer: Bool

  public init(
    intent: AgentTaskIntent, container: String?, scheme: String, configuration: String = "Debug",
    destination: Destination?, target: AppTarget?, startDevelopmentServer: Bool
  ) {
    self.intent = intent
    self.container = container
    self.scheme = scheme
    self.configuration = configuration
    self.destination = destination
    self.target = target
    self.startDevelopmentServer = startDevelopmentServer
  }

  public var destinationSpecifier: String? {
    destination.map { "platform=iOS Simulator,id=\($0.udid)" }
  }

  public var buildFingerprint: String {
    [scheme, configuration, destination?.runtime ?? "unknown", target?.bundleID ?? "unknown"]
      .joined(separator: "|")
  }
}

public struct JourneySelector: Codable, Hashable, Sendable {
  public var identifier: String?
  public var label: String?
  public var type: String?

  public init(identifier: String? = nil, label: String? = nil, type: String? = nil) {
    self.identifier = identifier
    self.label = label
    self.type = type
  }

  public var elementSelector: ElementSelector? {
    if let identifier, !identifier.isEmpty { return .accessibilityIdentifier(identifier) }
    if let label, let type, !label.isEmpty, !type.isEmpty {
      return .labelType(label: label, type: type)
    }
    return nil
  }
}

public struct JourneyStep: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var title: String
  public var criterionID: String?
  /// Opaque, screen-bound ID returned by currentUI.actions. Preferred over model-authored selectors.
  public var actionID: String?
  public var selector: JourneySelector?
  public var action: String?
  public var text: String?
  /// Optional post-action assertion. Unlike the legacy assertVisible flag, this does not re-assert
  /// the control that was just tapped and may have disappeared during navigation.
  public var expectVisible: JourneySelector?
  public var expectScreenChanged: Bool?
  public var assertVisible: Bool

  public init(
    id: String, title: String, criterionID: String? = nil, actionID: String? = nil,
    selector: JourneySelector? = nil, action: String? = nil, text: String? = nil,
    expectVisible: JourneySelector? = nil, expectScreenChanged: Bool? = nil,
    assertVisible: Bool = false
  ) {
    self.id = id
    self.title = title
    self.criterionID = criterionID
    self.actionID = actionID
    self.selector = selector
    self.action = action
    self.text = text
    self.expectVisible = expectVisible
    self.expectScreenChanged = expectScreenChanged
    self.assertVisible = assertVisible
  }

  public var assertsCurrentActionVisibility: Bool {
    action == nil && assertVisible && expectVisible == nil
  }

  public var requiresScreenChange: Bool {
    expectScreenChanged == true || (action != nil && assertVisible && expectVisible == nil)
  }
}

public enum JourneyStatus: String, Codable, Equatable, Sendable {
  case preparing
  case ready
  case running
  case passed
  case failed
  case cancelled
}

public enum JourneyStepStatus: String, Codable, Equatable, Sendable {
  case waiting
  case running
  case passed
  case failed
}

public struct JourneyStepResult: Codable, Identifiable, Sendable {
  public var id: String { step.id }
  public var step: JourneyStep
  public var status: JourneyStepStatus
  public var detail: String
  public var evidenceIDs: [UUID]

  public init(
    step: JourneyStep, status: JourneyStepStatus = .waiting, detail: String = "",
    evidenceIDs: [UUID] = []
  ) {
    self.step = step
    self.status = status
    self.detail = detail
    self.evidenceIDs = evidenceIDs
  }
}

public struct JourneyRecord: Codable, Identifiable, Sendable {
  public var id: UUID
  public var goal: String
  public var status: JourneyStatus
  public var steps: [JourneyStepResult]
  public var currentFingerprint: ScreenFingerprint?
  public var startedAt: Date
  public var updatedAt: Date

  public init(id: UUID = UUID(), goal: String, status: JourneyStatus = .preparing) {
    self.id = id
    self.goal = goal
    self.status = status
    self.steps = []
    self.startedAt = Date()
    self.updatedAt = Date()
  }
}

public enum RuntimeEventKind: String, Codable, Equatable, Sendable {
  case sessionConfigured
  case sessionAttached
  case buildStarted
  case buildFinished
  case appLaunched
  case previewAvailable
  case journeyStarted
  case journeyReady
  case journeyStepStarted
  case journeyStepFinished
  case journeyFinished
  case uiAction
  case assertion
  case screenshot
  case warning
}

public struct RuntimeEvent: Codable, Identifiable, Sendable {
  public var id: Int { sequence }
  public var sequence: Int
  public var kind: RuntimeEventKind
  public var message: String
  public var journeyID: UUID?
  public var stepID: String?
  public var target: AppTarget?
  public var destinationUDID: String?
  public var artifactPath: String?
  public var createdAt: Date

  public init(
    sequence: Int = 0, kind: RuntimeEventKind, message: String, journeyID: UUID? = nil,
    stepID: String? = nil, target: AppTarget? = nil, destinationUDID: String? = nil,
    artifactPath: String? = nil, createdAt: Date = Date()
  ) {
    self.sequence = sequence
    self.kind = kind
    self.message = message
    self.journeyID = journeyID
    self.stepID = stepID
    self.target = target
    self.destinationUDID = destinationUDID
    self.artifactPath = artifactPath
    self.createdAt = createdAt
  }
}

public struct AgentToolTraceEntry: Codable, Hashable, Sendable {
  public var name: String
  public var arguments: JSONValue

  public init(_ name: String, arguments: JSONValue = .object([:])) {
    self.name = name
    self.arguments = arguments
  }
}

public struct AgentToolTraceReport: Codable, Equatable, Sendable {
  public var violations: [String]
  public var usedCompositeJourney: Bool
  public var submittedCompletion: Bool
  public var passed: Bool { violations.isEmpty }

  public init(
    violations: [String], usedCompositeJourney: Bool, submittedCompletion: Bool
  ) {
    self.violations = violations
    self.usedCompositeJourney = usedCompositeJourney
    self.submittedCompletion = submittedCompletion
  }
}

/// Deterministic evaluation used by fake-agent and captured-trace tests. It verifies behavior at
/// the host boundary, so the contract is identical for every ACP-compatible model adapter.
public enum AgentToolTraceValidator {
  public static func validate(
    intent: AgentTaskIntent, trace: [AgentToolTraceEntry], requiresCompletion: Bool = true
  ) -> AgentToolTraceReport {
    var violations: [String] = []
    let allowed = Set(AgentRuntimeToolCatalog.tools(for: intent.kind).map(\.name))
    for entry in trace where !allowed.contains(entry.name) {
      violations.append("\(entry.name) is outside the host tool policy")
    }

    let journeyIndex = trace.firstIndex { $0.name == "journey.run" }
    if intent.requiresRunningApp, journeyIndex == nil {
      violations.append("journey.run was not used")
    }
    if let firstDirectUI = trace.firstIndex(where: { ["ui.perform", "ui.navigate"].contains($0.name) }) {
      if journeyIndex.map({ firstDirectUI < $0 }) ?? true {
        violations.append("UI interaction occurred before the host-owned journey")
      }
    }

    let submittedCompletion = trace.contains {
      $0.name == "journey.run" && $0.arguments["complete"]?.boolValue == true
    }
    let journeySteps = trace.filter { $0.name == "journey.run" }
      .flatMap { $0.arguments["steps"]?.arrayValue ?? [] }
    for step in journeySteps where step["action"]?.stringValue != nil
      && step["actionID"]?.stringValue == nil
    {
      violations.append("a journey action used a model-authored selector instead of actionID")
    }
    if submittedCompletion, intent.requiresRunningApp {
      if !journeySteps.contains(where: { $0["action"]?.stringValue != nil }) {
        violations.append("the completed journey did not exercise a host-issued app action")
      }
      if !journeySteps.contains(where: {
        $0["assertVisible"]?.boolValue == true || $0["expectScreenChanged"]?.boolValue == true
      }) {
        violations.append("the completed journey did not record a deterministic postcondition")
      }
    }
    if requiresCompletion, intent.requiresRunningApp, !submittedCompletion {
      violations.append("the journey was not completed with host-validated evidence")
    }
    return .init(
      violations: violations, usedCompositeJourney: journeyIndex != nil,
      submittedCompletion: submittedCompletion)
  }
}
