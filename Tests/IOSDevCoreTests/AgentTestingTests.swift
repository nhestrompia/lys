import Foundation
import Testing

@testable import IOSDevCore

@Test func verificationIntentReusesCurrentCheckoutWithoutWrites() {
  let intent = AgentTaskIntentRouter.classify("Test the quiz functionality and verify the score")
  #expect(intent.kind == .verifyCurrentApp)
  #expect(intent.workspacePolicy == .currentCheckout)
  #expect(intent.buildPolicy == .ifMissing)
  #expect(intent.appStatePolicy == .preserve)
  #expect(!intent.allowsSourceWrites)
}

@Test func mutationIntentAlwaysUsesIsolation() {
  for prompt in [
    "Fix the quiz score and test it", "Add a retry button", "Refactor the profile flow",
  ] {
    let intent = AgentTaskIntentRouter.classify(prompt)
    #expect(intent.kind == .modifyAndVerify)
    #expect(intent.workspacePolicy == .isolatedWorktree)
    #expect(intent.buildPolicy == .ifStale)
    #expect(intent.allowsSourceWrites)
  }
}

@Test func sourceTestIntentDoesNotClaimSimulatorLifecycle() {
  let intent = AgentTaskIntentRouter.classify("Run the unit test suite")
  #expect(intent.kind == .runTests)
  #expect(!intent.requiresRunningApp)
  #expect(intent.buildPolicy == .never)
}

@Test func ambiguousPromptDoesNotAccidentallyGrantWriteAuthority() {
  let intent = AgentTaskIntentRouter.classify("What do you think?")
  #expect(intent.kind == .inspectCurrentApp)
  #expect(!intent.allowsSourceWrites)
  #expect(intent.appStatePolicy == .preserve)
}

@Test func journeySelectorOnlyCreatesDeterministicSelectors() {
  #expect(
    JourneySelector(identifier: "quiz.start").elementSelector
      == .accessibilityIdentifier("quiz.start"))
  #expect(
    JourneySelector(label: "Start Quiz", type: "Button").elementSelector
      == .labelType(label: "Start Quiz", type: "Button"))
  #expect(JourneySelector(label: "Start Quiz").elementSelector == nil)
}

@Test func tappedNavigationControlIsNotReassertedAfterItDisappears() {
  let navigation = JourneyStep(
    id: "open-quiz", title: "Open Practice Quiz", actionID: "action_start",
    action: "tap", assertVisible: true)
  #expect(!navigation.assertsCurrentActionVisibility)
  #expect(navigation.requiresScreenChange)

  let currentAssertion = JourneyStep(
    id: "quiz-visible", title: "Quiz is visible", actionID: "action_answer_a",
    assertVisible: true)
  #expect(currentAssertion.assertsCurrentActionVisibility)
  #expect(!currentAssertion.requiresScreenChange)
}

@Test func sparseAgentJourneyStepDoesNotRequireLegacyAssertionFlag() throws {
  let payload = JSONValue.array([
    .object([
      "id": .string("start"),
      "title": .string("Start quiz"),
      "actionID": .string("action_start"),
      "action": .string("tap"),
      "expectScreenChanged": .bool(true),
    ])
  ])
  let data = try JSONEncoder().encode(payload)
  let steps = try JSONDecoder().decode([JourneyStep].self, from: data)

  let step = try #require(steps.first)
  #expect(step.id == "start")
  #expect(step.actionID == "action_start")
  #expect(step.action == "tap")
  #expect(step.expectScreenChanged == true)
  #expect(!step.assertVisible)
}

@Test func goldenDeclaredFlowTraceUsesOneHostOwnedCallWithoutLifecycleThrash() {
  let intent = AgentTaskIntentRouter.classify("Test the quiz and verify its score")
  let trace = [
    AgentToolTraceEntry("workspace.describe"),
    AgentToolTraceEntry("app.describe"),
    AgentToolTraceEntry("flow.list"),
    AgentToolTraceEntry(
      "flow.run",
      arguments: .object([
        "goal": .string("Verify quiz scoring"), "blueprintID": .string("quiz.complete"),
      ])),
    AgentToolTraceEntry("evidence.summary"),
  ]
  let report = AgentToolTraceValidator.validate(intent: intent, trace: trace)
  #expect(report.passed)
  #expect(report.usedCompositeJourney)
  #expect(report.submittedCompletion)
}

@Test func badAgentTraceCannotHideLifecycleThrashOrMissingEvidence() {
  let intent = AgentTaskIntentRouter.classify("Test the quiz")
  let trace = [
    AgentToolTraceEntry("devserver.stop"), AgentToolTraceEntry("build.run"),
    AgentToolTraceEntry("flow.step"),
  ]
  let report = AgentToolTraceValidator.validate(intent: intent, trace: trace)
  #expect(!report.passed)
  #expect(report.violations.contains { $0.contains("devserver.stop") })
  #expect(report.violations.contains { $0.contains("build.run") })
  #expect(report.violations.contains { $0.contains("flow.run") })
  #expect(report.violations.contains { $0.contains("evidence") })
}
