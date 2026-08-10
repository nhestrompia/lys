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
