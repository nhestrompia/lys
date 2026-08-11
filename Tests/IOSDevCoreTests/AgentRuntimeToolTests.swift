import Testing

@testable import IOSDevCore

@Test func verificationCatalogHidesLifecycleAndBuildPrimitives() {
  let names = Set(AgentRuntimeToolCatalog.tools(for: .verifyCurrentApp).map(\.name))
  #expect(names.contains("journey.run"))
  #expect(names.contains("ui.actions"))
  #expect(names.contains("ui.perform"))
  #expect(!names.contains("build.run"))
  #expect(!names.contains("devserver.stop"))
  #expect(!names.contains("app.terminate"))
}

@Test func directUIActionsRequireHostIssuedOpaqueIDs() throws {
  let perform = try #require(
    AgentRuntimeToolCatalog.definition(named: "ui.perform", for: .verifyCurrentApp))
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: perform,
      arguments: .object([
        "selector": .object(["label": .string("Start quiz"), "type": .string("Button")]),
        "action": .string("tap"),
      ])) == "arguments.actionID is required")
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: perform,
      arguments: .object(["actionID": .string("action_123"), "action": .string("tap")]))
      == nil)
}

@Test func mutationCatalogStillPrefersJourneyButPermitsExplicitBuildAndTests() {
  let names = Set(AgentRuntimeToolCatalog.tools(for: .modifyAndVerify).map(\.name))
  #expect(names.contains("journey.run"))
  #expect(names.contains("build.run"))
  #expect(names.contains("test.run"))
  #expect(!names.contains("devserver.stop"))
}

@Test func allRuntimeToolSchemasRejectUnknownArguments() {
  for tool in AgentRuntimeToolCatalog.tools(for: .modifyAndVerify) {
    #expect(tool.inputSchema["additionalProperties"] == .bool(false))
  }
}

@Test func hostPolicyRejectsHallucinatedLifecycleCallsEvenWhenRuntimeSupportsThem() {
  #expect(AgentRuntimeToolCatalog.allows("journey.run", for: .verifyCurrentApp))
  #expect(!AgentRuntimeToolCatalog.allows("build.run", for: .verifyCurrentApp))
  #expect(!AgentRuntimeToolCatalog.allows("devserver.stop", for: .verifyCurrentApp))
  #expect(!AgentRuntimeToolCatalog.allows("app.reset_data", for: .modifyAndVerify))
}

@Test func runtimeToolArgumentsCannotOverrideHostSelectedContext() throws {
  let screenshot = try #require(
    AgentRuntimeToolCatalog.definition(named: "screenshot.capture", for: .verifyCurrentApp))
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: screenshot, arguments: .object(["udid": .string("other-simulator")])) != nil)

  let journey = try #require(
    AgentRuntimeToolCatalog.definition(named: "journey.run", for: .verifyCurrentApp))
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(for: journey, arguments: .object([:]))
      == "arguments.goal is required")
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: journey,
      arguments: .object([
        "goal": .string("Test quiz"),
        "steps": .array([
          .object([
            "id": .string("start"), "title": .string("Start quiz"),
            "actionID": .string("action_start"),
            "selector": .object([
              "identifier": .string("quiz.start"), "coordinate": .number(0.5),
            ]),
          ])
        ]),
      ]))?.contains("coordinate") == true)
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: journey,
      arguments: .object([
        "goal": .string("Test quiz"),
        "steps": .array([
          .object([
            "id": .string("visible"), "title": .string("Quiz is visible"),
            "actionID": .string("action_quiz"), "action": .string("assert"),
          ])
        ]),
      ]))?.contains("must be one of") == true)
}
