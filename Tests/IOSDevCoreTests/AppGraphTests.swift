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

@Test func graphNavigationKeepsDestinationFamiliesSeparate() async {
  let graph = AppGraph()
  let home = fingerprint("home")
  let phoneProfile = fingerprint("phone-profile")
  let padProfile = fingerprint("pad-profile")
  _ = await graph.observe(
    from: home, to: phoneProfile, selector: .accessibilityIdentifier("phone-profile"),
    build: "17F", destinationFamily: "iPhone")
  _ = await graph.observe(
    from: home, to: padProfile, selector: .accessibilityIdentifier("pad-profile"),
    build: "17F", destinationFamily: "iPad")

  #expect(
    await graph.path(from: home, to: phoneProfile, build: "17F", destinationFamily: "iPhone")?
      .first?.destinationFamily == "iPhone")
  #expect(
    await graph.path(from: home, to: padProfile, build: "17F", destinationFamily: "iPad")?
      .first?.destinationFamily == "iPad")
  #expect(
    await graph.path(from: home, to: padProfile, build: "17F", destinationFamily: "iPhone")
      == nil)
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
    owningApplication: "app", availableActions: [], accessible: true)
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
    owningApplication: "app", accessible: true)
  let second = UIElement(
    type: "StaticText", label: "Start", frame: .init(x: 20, y: 200, width: 100, height: 44),
    childPath: "0.2", xpath: "/XCUIElementTypeApplication[1]/XCUIElementTypeStaticText[2]",
    owningApplication: "app", accessible: true)
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

@Test func hierarchyParserBuildsActionsAcrossNativeSwiftUIAndCrossPlatformApps() throws {
  let xml = """
    <XCUIElementTypeApplication type="XCUIElementTypeApplication" bundleId="com.example.app" enabled="true" visible="true" accessible="false" x="0" y="0" width="402" height="874">
      <XCUIElementTypeButton type="XCUIElementTypeButton" name="quiz.start" label="Start quiz" enabled="true" visible="true" accessible="true" x="20" y="80" width="362" height="52"/>
      <XCUIElementTypeSwitch type="XCUIElementTypeSwitch" name="settings.sound" label="Sound" value="0" enabled="true" visible="true" accessible="true" x="20" y="145" width="362" height="44"/>
      <XCUIElementTypeStaticText type="XCUIElementTypeStaticText" label="Decorative heading" enabled="true" visible="true" accessible="false" x="20" y="200" width="200" height="30"/>
      <XCUIElementTypeOther type="XCUIElementTypeOther" name="rn.practice" label="Practice Quiz" enabled="true" visible="true" accessible="true" x="20" y="240" width="362" height="70"/>
      <XCUIElementTypeOther type="XCUIElementTypeOther" name="flutter.answer" label="Answer A" enabled="true" visible="true" accessible="true" x="20" y="320" width="362" height="52"/>
      <XCUIElementTypeButton type="XCUIElementTypeButton" name="covered" label="Covered control" enabled="true" visible="true" accessible="true" hittable="false" x="20" y="380" width="362" height="52"/>
      <XCUIElementTypeTextField type="XCUIElementTypeTextField" name="profile.name" label="Name" focused="false" enabled="true" visible="true" accessible="true" x="20" y="440" width="362" height="52"/>
      <XCUIElementTypeScrollView type="XCUIElementTypeScrollView" enabled="true" visible="true" accessible="false" x="0" y="510" width="402" height="300">
        <XCUIElementTypeWebView type="XCUIElementTypeWebView" name="checkout.web" enabled="true" visible="true" accessible="false" x="0" y="510" width="402" height="300">
          <XCUIElementTypeLink type="XCUIElementTypeLink" name="checkout" label="Checkout" enabled="true" visible="true" accessible="true" x="20" y="540" width="150" height="44"/>
        </XCUIElementTypeWebView>
      </XCUIElementTypeScrollView>
    </XCUIElementTypeApplication>
    """
  let elements = try WDAHierarchyParser.parse(xml)
  let screen = ScreenFingerprint.make(elements: elements, modal: false, navigationTitle: nil)
  let actions = UIActionCatalog.capabilities(elements: elements, fingerprint: screen)

  #expect(actions.contains { $0.title == "Start quiz" && $0.actions == ["tap"] })
  #expect(actions.contains { $0.title == "Sound" && $0.actions == ["tap"] })
  #expect(
    actions.contains {
      $0.title == "Practice Quiz" && $0.source == "accessibilityContainer"
    })
  #expect(
    actions.contains {
      $0.title == "Answer A" && $0.source == "accessibilityContainer"
    })
  #expect(
    actions.contains {
      $0.title == "Name" && $0.actions == ["tap", "type", "clear"]
    })
  #expect(actions.contains { $0.title == "Checkout" && $0.actions == ["tap"] })
  #expect(actions.contains { $0.role == "ScrollView" && $0.actions.contains("scrollDown") })
  #expect(actions.contains { $0.role == "WebView" && $0.actions.contains("scrollDown") })
  #expect(!actions.contains { $0.title == "Decorative heading" })
  #expect(!actions.contains { $0.title == "Covered control" })
}

@Test func malformedHierarchyFailsInsteadOfInventingAnActionGraph() {
  #expect(throws: (any Error).self) {
    try WDAHierarchyParser.parse(
      "<XCUIElementTypeApplication><XCUIElementTypeButton label=\"Start\">")
  }
}

@Test func interactionFingerprintDetectsNoNavigationStateChanges() {
  let frame = ElementFrame(x: 20, y: 100, width: 280, height: 52)
  let before = UIElement(
    type: "TextField", identifier: "answer", label: "Answer", value: "",
    focused: false, frame: frame, childPath: "0.1", owningApplication: "app",
    availableActions: ["tap", "type", "clear"])
  var focused = before
  focused.focused = true
  var typed = focused
  typed.value = "Athens"
  var scrolled = typed
  scrolled.frame.y = 40

  #expect(
    ScreenFingerprint.make(elements: [before], modal: false, navigationTitle: nil)
      == ScreenFingerprint.make(elements: [typed], modal: false, navigationTitle: nil))
  #expect(
    UIInteractionStateFingerprint.make(elements: [before])
      != UIInteractionStateFingerprint.make(elements: [focused]))
  #expect(
    UIInteractionStateFingerprint.make(elements: [focused])
      != UIInteractionStateFingerprint.make(elements: [typed]))
  #expect(
    UIInteractionStateFingerprint.make(elements: [typed])
      != UIInteractionStateFingerprint.make(elements: [scrolled]))
}

@Test func actionCatalogPrefersNestedControlOverNonCausalCardWrapper() {
  let wrapper = UIElement(
    type: "Other", identifier: "quiz.card", label: "Quiz. Practice mixed topics",
    frame: .init(x: 20, y: 80, width: 362, height: 220), childPath: "0.1",
    owningApplication: "app", accessible: true)
  let button = UIElement(
    type: "Button", identifier: "quiz.start", label: "Start quiz",
    frame: .init(x: 40, y: 220, width: 322, height: 52), childPath: "0.1.1",
    owningApplication: "app", availableActions: ["tap"], accessible: true)
  let elements = [wrapper, button]
  let screen = ScreenFingerprint.make(elements: elements, modal: false, navigationTitle: nil)
  let actions = UIActionCatalog.capabilities(elements: elements, fingerprint: screen)

  #expect(actions.map(\.title) == ["Start quiz"])
}

@Test func finiteFlowProgressPreventsIntermediateCompletion() throws {
  let frame = ElementFrame(x: 0, y: 0, width: 120, height: 30)
  let firstQuestion = UIElement(
    type: "StaticText", label: "1 of 10", frame: frame, childPath: "0.1",
    owningApplication: "app")
  let lastQuestion = UIElement(
    type: "StaticText", label: "Question 10 / 10", frame: frame, childPath: "0.2",
    owningApplication: "app")
  let completed = UIElement(
    type: "StaticText", label: "Completed 10 out of 10", frame: frame, childPath: "0.3",
    owningApplication: "app")
  let tabAnnouncement = UIElement(
    type: "Button",
    label: "Home, tab, 1 of 14, AI Chat, Learn, Favorites, Settings",
    frame: frame, childPath: "0.4", owningApplication: "app", availableActions: ["tap"])
  let hiddenProgress = UIElement(
    type: "StaticText", label: "2 of 10", visible: false, frame: frame,
    childPath: "0.5", owningApplication: "app")

  let first = try #require(UIFlowProgressDetector.detect(in: [firstQuestion]))
  #expect(first.current == 1)
  #expect(first.total == 10)
  #expect(first.remaining == 9)
  #expect(!first.isComplete)
  #expect(UIFlowProgressDetector.detect(in: [lastQuestion])?.isComplete == false)
  #expect(UIFlowProgressDetector.detect(in: [completed])?.isComplete == true)
  #expect(UIFlowProgressDetector.detect(in: [tabAnnouncement]) == nil)
  #expect(UIFlowProgressDetector.detect(in: [hiddenProgress]) == nil)
}
