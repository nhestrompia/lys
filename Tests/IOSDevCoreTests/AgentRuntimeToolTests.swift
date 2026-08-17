import Foundation
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

@Test func simulatorManagementToolsAreAvailableForDeviceValidation() throws {
  let names = Set(AgentRuntimeToolCatalog.tools(for: .modifyAndVerify).map(\.name))
  for name in [
    "simulator.active", "simulator.list_active", "simulator.add", "simulator.remove",
    "simulator.focus", "simulator.configure",
  ] {
    #expect(names.contains(name))
  }
  let add = try #require(
    AgentRuntimeToolCatalog.definition(named: "simulator.add", for: .modifyAndVerify))
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: add, arguments: .object(["platform": .string("iPadOS")])) == nil)
  #expect(
    AgentRuntimeToolCatalog.argumentViolation(
      for: add, arguments: .object(["platform": .string("Android")])) != nil)
}

@Test func runtimeSessionConfigurationCarriesFocusedAndActiveDestinations() throws {
  let iphone = Destination(
    udid: "iphone", name: "iPhone 17 Pro", deviceType: "iPhone 17 Pro",
    runtime: "iOS 26.5", state: "Booted")
  let ipad = Destination(
    udid: "ipad", name: "iPad Pro 13-inch", deviceType: "iPad Pro 13-inch",
    runtime: "iPadOS 26.5", state: "Booted")
  let intent = AgentTaskIntentRouter.classify("Make the layout work on iPad")
  let configuration = RuntimeSessionConfiguration(
    intent: intent, container: nil, scheme: "Demo", destination: iphone,
    destinations: [iphone, ipad], focusedDestinationID: ipad.udid,
    requiredDestinationUDIDs: [iphone.udid, ipad.udid],
    requiredDestinationFamilies: [], target: nil,
    startDevelopmentServer: false)
  let roundTrip = try JSONDecoder().decode(
    RuntimeSessionConfiguration.self,
    from: JSONEncoder().encode(configuration))
  #expect(roundTrip.destinations.map(\.udid) == ["iphone", "ipad"])
  #expect(roundTrip.focusedDestinationID == "ipad")
  #expect(roundTrip.requiredDestinationUDIDs == ["iphone", "ipad"])
  #expect(roundTrip.requiredDestinationFamilies.isEmpty)
  #expect(roundTrip.destination?.udid == "iphone")
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
