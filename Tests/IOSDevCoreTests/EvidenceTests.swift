import Testing

@testable import IOSDevCore

@Test func mutationMakesEarlierEvidenceStale() async throws {
  let ledger = EvidenceLedger()
  try await ledger.record(Evidence(kind: .build, status: .passed, taskGeneration: 0))
  #expect(
    await ledger.verify(.init(codeChanged: true, uiChanged: false, testsChanged: false)).status
      == .verified)
  _ = await ledger.mutate()
  let report = await ledger.verify(.init(codeChanged: true, uiChanged: false, testsChanged: false))
  #expect(report.status == .partiallyVerified)
  #expect(report.staleEvidence.count == 1)
}

@Test func coordinateActionCannotSatisfyUIVerification() async throws {
  let ledger = EvidenceLedger()
  for item in [
    Evidence(kind: .build, status: .passed, taskGeneration: 0),
    Evidence(kind: .launch, status: .passed, taskGeneration: 0),
    Evidence(
      kind: .uiAssertion, status: .passed, taskGeneration: 0, criterionID: "profile",
      deterministic: false),
    Evidence(kind: .screenshot, status: .passed, taskGeneration: 0),
  ] { try await ledger.record(item) }
  let report = await ledger.verify(
    .init(codeChanged: true, uiChanged: true, testsChanged: false, criterionIDs: ["profile"]))
  #expect(report.status == .partiallyVerified)
  #expect(report.missing.contains { $0.contains("Deterministic") })
}

@Test func unacknowledgedCrashFailsVerification() async throws {
  let ledger = EvidenceLedger()
  for item in [
    Evidence(kind: .build, status: .passed, taskGeneration: 0),
    Evidence(kind: .launch, status: .passed, taskGeneration: 0),
    Evidence(kind: .uiAssertion, status: .passed, taskGeneration: 0, criterionID: "profile"),
    Evidence(kind: .screenshot, status: .passed, taskGeneration: 0),
    Evidence(kind: .runtimeLog, status: .failed, taskGeneration: 0, diagnosticSummary: "crash"),
  ] { try await ledger.record(item) }
  #expect(
    await ledger.verify(
      .init(codeChanged: true, uiChanged: true, testsChanged: false, criterionIDs: ["profile"])
    ).status == .failed)
  #expect(
    await ledger.verify(.init(codeChanged: true, uiChanged: false, testsChanged: false)).status
      == .failed)
}

@Test func failedOptionalEvidenceDoesNotFailRequiredBuild() async throws {
  let ledger = EvidenceLedger()
  try await ledger.record(Evidence(kind: .build, status: .passed, taskGeneration: 0))
  try await ledger.record(
    Evidence(kind: .uiAction, status: .failed, taskGeneration: 0, deterministic: false))
  let report = await ledger.verify(
    .init(codeChanged: true, uiChanged: false, testsChanged: false))
  #expect(report.status == .verified)
}

@Test func successfulJourneyRetrySupersedesItsEarlierFailedAssertion() async throws {
  let ledger = EvidenceLedger()
  for item in [
    Evidence(kind: .launch, status: .passed, taskGeneration: 0),
    Evidence(
      kind: .uiAssertion, status: .failed, taskGeneration: 0, criterionID: "journey-1",
      diagnosticSummary: "First action did not change the screen"),
    Evidence(
      kind: .uiAssertion, status: .passed, taskGeneration: 0, criterionID: "journey-1",
      diagnosticSummary: "Retry reached the quiz"),
    Evidence(kind: .screenshot, status: .passed, taskGeneration: 0),
  ] { try await ledger.record(item) }
  let report = await ledger.verify(
    .init(codeChanged: false, uiChanged: true, testsChanged: false))
  #expect(report.status == .verified)
  #expect(report.currentEvidence.first { $0.status == .failed }?.acknowledged == true)
}

@Test func hierarchyInspectorHidesEmptyStructuralNodes() {
  let frame = ElementFrame(x: 0, y: 0, width: 100, height: 40)
  let elements = [
    UIElement(
      type: "Application", identifier: "Ellinix", frame: frame, childPath: "0",
      owningApplication: "com.nhest.ellinix"),
    UIElement(
      type: "Window", frame: frame, childPath: "0/0",
      owningApplication: "com.nhest.ellinix"),
    UIElement(
      type: "Other", frame: frame, childPath: "0/0/0",
      owningApplication: "com.nhest.ellinix"),
    UIElement(
      type: "Button", identifier: "profile", label: "Profile", frame: frame,
      childPath: "0/0/1", owningApplication: "com.nhest.ellinix"),
  ]
  let meaningful = UIHierarchyInspector.meaningfulElements(from: elements)
  #expect(meaningful.count == 1)
  #expect(meaningful.first?.identifier == "profile")
}
