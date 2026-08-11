import Testing

@testable import IOSDevCore

private func fingerprint(_ value: String) -> ScreenFingerprint {
  .init(digest: value, owningApplication: "com.example.app")
}

@Test func breadthFirstNavigationUsesOnlyDeterministicCurrentEdges() async {
  let graph = AppGraph()
  let a = fingerprint("a")
  let b = fingerprint("b")
  let c = fingerprint("c")
  let d = fingerprint("d")
  _ = await graph.observe(
    from: a, to: b, selector: .accessibilityIdentifier("profile"), build: "17F")
  _ = await graph.observe(
    from: b, to: d, selector: .labelType(label: "Settings", type: "Button"), build: "17F")
  _ = await graph.observe(from: a, to: c, selector: .coordinate(x: 1, y: 2), build: "17F")
  _ = await graph.observe(
    from: c, to: d, selector: .accessibilityIdentifier("finish"), build: "17F")
  let path = await graph.path(from: a, to: d, build: "17F")
  #expect(path?.count == 2)
  #expect(path?.first?.to == b)
  #expect(await graph.path(from: a, to: d, build: "new-build") == nil)
}

@Test func failedEdgeBecomesStale() async {
  let graph = AppGraph()
  let a = fingerprint("a")
  let b = fingerprint("b")
  let edge = await graph.observe(
    from: a, to: b, selector: .accessibilityIdentifier("next"), build: "17F")
  #expect(edge != nil)
  await graph.recordFailure(edge!.id)
  #expect(await graph.path(from: a, to: b, build: "17F") == nil)
}

@Test func fingerprintExcludesChangingValues() {
  let frame = ElementFrame(x: 0, y: 0, width: 20, height: 20)
  let first = UIElement(
    type: "TextField", identifier: "clock", label: "Clock", value: "10:00", frame: frame,
    childPath: "0/1", owningApplication: "app")
  let second = UIElement(
    type: "TextField", identifier: "clock", label: "Clock", value: "10:01", frame: frame,
    childPath: "0/1", owningApplication: "app")
  #expect(
    ScreenFingerprint.make(elements: [first], modal: false, navigationTitle: nil)
      == ScreenFingerprint.make(elements: [second], modal: false, navigationTitle: nil))
}

@Test func fingerprintTracksInteractiveStateChanges() {
  let frame = ElementFrame(x: 0, y: 0, width: 20, height: 20)
  let idle = UIElement(
    type: "Button", identifier: "quiz.answer.a", label: "A", selected: false, frame: frame,
    childPath: "0/1", owningApplication: "app")
  let selected = UIElement(
    type: "Button", identifier: "quiz.answer.a", label: "A", selected: true, frame: frame,
    childPath: "0/1", owningApplication: "app")
  #expect(
    ScreenFingerprint.make(elements: [idle], modal: false, navigationTitle: nil)
      != ScreenFingerprint.make(elements: [selected], modal: false, navigationTitle: nil))
}

@Test func graphSnapshotCanBeRestoredForLaterJourneys() async {
  let graph = AppGraph()
  let a = fingerprint("a")
  let b = fingerprint("b")
  _ = await graph.observe(
    from: a, to: b, selector: .accessibilityIdentifier("quiz.start"), build: "build-1")
  let restored = AppGraph()
  await restored.replace(with: graph.codableSnapshot())
  #expect(await restored.path(from: a, to: b, build: "build-1")?.count == 1)
}

@Test func textInputEdgesAreRecordedButNeverReplayedWithoutSensitiveInput() async {
  let graph = AppGraph()
  let a = fingerprint("a")
  let b = fingerprint("b")
  let edge = await graph.observe(
    from: a, to: b, selector: .accessibilityIdentifier("quiz.name"), build: "build-1",
    action: "type")
  #expect(edge?.action == "type")
  #expect(await graph.path(from: a, to: b, build: "build-1") == nil)
}

@Test func actionCatalogMakesVisibleQuizControlsAgentActionableWithoutGuessedRoles() throws {
  let button = UIElement(
    type: "Button", label: "Start quiz", frame: .init(x: 20, y: 100, width: 280, height: 52),
    childPath: "0.1.4", owningApplication: "app", availableActions: ["tap"])
  // React Native frequently exposes the text inside a Pressable without a Button role. The host
  // still issues a screen-bound action rather than asking a model to guess a coordinate.
  let pressableText = UIElement(
    type: "StaticText", label: "Choose topics",
    frame: .init(x: 24, y: 180, width: 140, height: 44), childPath: "0.1.5.1",
    owningApplication: "app", availableActions: [])
  let elements = [button, pressableText]
  let screen = ScreenFingerprint.make(elements: elements, modal: false, navigationTitle: nil)
  let actions = UIActionCatalog.capabilities(elements: elements, fingerprint: screen)
  #expect(actions.map(\.title).contains("Start quiz"))
  #expect(actions.map(\.title).contains("Choose topics"))

  let chooseTopics = try #require(actions.first { $0.title == "Choose topics" })
  #expect(chooseTopics.actions == ["tap"])
  #expect(chooseTopics.resolution == .semantic || chooseTopics.resolution == .screenBound)
  let resolved = try #require(
    UIActionCatalog.resolve(
      actionID: chooseTopics.id, action: "tap", elements: elements, fingerprint: screen))
  #expect(resolved.element.childPath == "0.1.5.1")
  let stale = UIActionCatalog.resolve(
    actionID: chooseTopics.id, action: "tap", elements: elements,
    fingerprint: fingerprint("different-screen"))
  #expect(stale?.capability.id == nil)
}

@Test func appGraphPersistsTheActionCatalogForEveryObservedScreen() async {
  let graph = AppGraph()
  let screen = fingerprint("quiz-screen")
  let action = UIActionCapability(
    id: "action-start", title: "Start quiz", role: "Button", actions: ["tap"],
    resolution: .semantic, enabled: true)
  await graph.observeScreen(screen, name: "Quiz", actions: [action])
  #expect(await graph.codableSnapshot().nodes.first?.actions == [action])
}

@Test func duplicateLabelsRemainIndividuallyActionableThroughScreenBoundXPath() throws {
  let first = UIElement(
    type: "StaticText", label: "Start", frame: .init(x: 20, y: 100, width: 100, height: 44),
    childPath: "0.1", xpath: "/XCUIElementTypeApplication[1]/XCUIElementTypeStaticText[1]",
    owningApplication: "app")
  let second = UIElement(
    type: "StaticText", label: "Start", frame: .init(x: 20, y: 200, width: 100, height: 44),
    childPath: "0.2", xpath: "/XCUIElementTypeApplication[1]/XCUIElementTypeStaticText[2]",
    owningApplication: "app")
  let elements = [first, second]
  let screen = ScreenFingerprint.make(elements: elements, modal: false, navigationTitle: nil)
  let actions = UIActionCatalog.capabilities(elements: elements, fingerprint: screen)
  #expect(actions.count == 2)
  #expect(actions.allSatisfy { $0.resolution == .screenBound })
  let resolved = try #require(
    UIActionCatalog.resolve(
      actionID: actions[1].id, action: "tap", elements: elements, fingerprint: screen))
  #expect(
    resolved.selector
      == .hierarchyPath("/XCUIElementTypeApplication[1]/XCUIElementTypeStaticText[2]"))
}
