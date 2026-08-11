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

@Test func goldenQuizTraceUsesOneHostOwnedJourneyWithoutLifecycleThrash() {
  let intent = AgentTaskIntentRouter.classify("Test the quiz and verify its score")
  let trace = [
    AgentToolTraceEntry("workspace.describe"),
    AgentToolTraceEntry(
      "journey.run", arguments: .object(["goal": .string("Verify quiz scoring")])),
    AgentToolTraceEntry(
      "journey.run",
      arguments: .object([
        "goal": .string("Verify quiz scoring"), "journeyID": .string("journey-1"),
        "steps": .array([]), "complete": .bool(true),
      ])),
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
    AgentToolTraceEntry("ui.perform"),
  ]
  let report = AgentToolTraceValidator.validate(intent: intent, trace: trace)
  #expect(!report.passed)
  #expect(report.violations.contains { $0.contains("devserver.stop") })
  #expect(report.violations.contains { $0.contains("build.run") })
  #expect(report.violations.contains { $0.contains("journey.run") })
  #expect(report.violations.contains { $0.contains("evidence") })
}
