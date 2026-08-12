import Testing

@testable import IOSDevCore

@Test func verificationCatalogHidesLifecycleAndBuildPrimitives() {
  let names = Set(AgentRuntimeToolCatalog.tools(for: .verifyCurrentApp).map(\.name))
  #expect(names.contains("app.describe"))
  #expect(names.contains("flow.list"))
  #expect(names.contains("flow.run"))
  #expect(names.contains("flow.step"))
  #expect(names.contains("flow.finish"))
  #expect(names.contains("flow.stop"))
  #expect(names.contains("evidence.summary"))
  #expect(!names.contains("journey.run"))
  #expect(!names.contains("ui.actions"))
  #expect(!names.contains("ui.perform"))
  #expect(!names.contains("build.run"))
  #expect(!names.contains("devserver.stop"))
  #expect(!names.contains("app.terminate"))
}

@Test func discoveryStepsRequireHostIssuedCapabilityIDs() throws {
  let perform = try #require(
    AgentRuntimeToolCatalog.definition(named: "flow.step", for: .verifyCurrentApp))
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: perform,
      arguments: .object([
        "flowID": .string("flow-1"),
        "action": .string("tap"),
      ])) == "arguments.capabilityID is required")
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: perform,
      arguments: .object([
        "flowID": .string("flow-1"), "capabilityID": .string("action_123"),
        "action": .string("tap"),
      ]))
      == nil)
}

@Test func mutationCatalogStillPrefersJourneyButPermitsExplicitBuildAndTests() {
  let names = Set(AgentRuntimeToolCatalog.tools(for: .modifyAndVerify).map(\.name))
  #expect(names.contains("flow.run"))
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
  #expect(AgentRuntimeToolCatalog.allows("flow.run", for: .verifyCurrentApp))
  #expect(!AgentRuntimeToolCatalog.allows("journey.run", for: .verifyCurrentApp))
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
    AgentRuntimeToolCatalog.definition(named: "flow.run", for: .verifyCurrentApp))
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(for: journey, arguments: .object([:]))
      == "arguments.goal is required")
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: journey,
      arguments: .object([
        "goal": .string("Test quiz"),
        "selector": .object(["label": .string("Start quiz")]),
      ]))?.contains("selector") == true)
}
