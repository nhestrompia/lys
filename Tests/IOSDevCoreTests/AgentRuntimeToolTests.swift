import Testing

@testable import IOSDevCore

@Test func verificationCatalogHidesLifecycleAndBuildPrimitives() {
  let names = Set(AgentRuntimeToolCatalog.tools(for: .verifyCurrentApp).map(\.name))
  #expect(names.contains("journey.run"))
  #expect(names.contains("ui.perform"))
  #expect(!names.contains("build.run"))
  #expect(!names.contains("devserver.stop"))
  #expect(!names.contains("app.terminate"))
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
            "selector": .object([
              "identifier": .string("quiz.start"), "coordinate": .number(0.5),
            ]),
          ])
        ]),
      ]))?.contains("coordinate") == true)
}
