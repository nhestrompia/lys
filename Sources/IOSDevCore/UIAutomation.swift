import CryptoKit
import Foundation

public struct ElementFrame: Codable, Hashable, Sendable {
  public var x: Double, y: Double, width: Double, height: Double
  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct UIElement: Codable, Identifiable, Hashable, Sendable {
  public var id: String { childPath }
  public var type: String
  public var identifier: String?
  public var label: String?
  public var value: String?
  public var enabled: Bool
  public var selected: Bool
  public var focused: Bool?
  public var visible: Bool?
  public var hittable: Bool
  /// Accessibility containers cover framework controls that XCTest exposes without a native
  /// Button/Link role (notably React Native, Flutter, and some hybrid views).
  public var accessible: Bool?
  public var frame: ElementFrame
  public var childPath: String
  public var xpath: String?
  public var owningApplication: String
  public var availableActions: [String]
  public init(
    type: String, identifier: String? = nil, label: String? = nil, value: String? = nil,
    enabled: Bool = true, selected: Bool = false, focused: Bool? = nil,
    visible: Bool? = true, hittable: Bool = true, frame: ElementFrame,
    childPath: String, xpath: String? = nil, owningApplication: String,
    availableActions: [String] = [], accessible: Bool? = nil
  ) {
    self.type = type
    self.identifier = identifier
    self.label = label
    self.value = value
    self.enabled = enabled
    self.selected = selected
    self.focused = focused
    self.visible = visible
    self.hittable = hittable
    self.accessible = accessible
    self.frame = frame
    self.childPath = childPath
    self.xpath = xpath
    self.owningApplication = owningApplication
    self.availableActions = availableActions
  }
}

public enum UIHierarchyInspector {
  /// Removes structural WDA nodes that are useful for protocol diagnostics but not for inspection.
  /// Containers with a real label, identifier, value, or action remain visible.
  public static func meaningfulElements(from elements: [UIElement]) -> [UIElement] {
    var seen = Set<String>()
    return elements.filter { element in
      let identifier = normalized(element.identifier)
      let label = normalized(element.label)
      let value = normalized(element.value)
      let hasContent =
        identifier != nil || label != nil || value != nil
        || !element.availableActions.isEmpty
      let structural =
        ["Application", "Window"].contains(element.type)
        || (element.type == "Other" && !hasContent)
      guard !structural, hasContent || element.hittable else { return false }

      let key = [
        element.type, identifier ?? "", label ?? "", value ?? "",
        String(
          format: "%.1f,%.1f,%.1f,%.1f", element.frame.x, element.frame.y,
          element.frame.width, element.frame.height),
      ].joined(separator: "|")
      return seen.insert(key).inserted
    }
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

public enum ElementSelector: Codable, Hashable, Sendable {
  case accessibilityIdentifier(String)
  case labelType(label: String, type: String)
  case ancestor(label: String, type: String, ancestorIdentifier: String)
  case hierarchyPath(String)
  case coordinate(x: Double, y: Double)

  public var deterministic: Bool { if case .coordinate = self { false } else { true } }
}

public enum UIActionResolution: String, Codable, Hashable, Sendable {
  /// WDA can address the element by accessibility identifier or unique label and role.
  case semantic
  /// The host resolves a stable hierarchy path against the exact current screen, then acts at
  /// the element's frame. The model never supplies a coordinate.
  case screenBound
}

public struct UIActionCapability: Codable, Identifiable, Hashable, Sendable {
  public var id: String
  public var title: String
  public var role: String
  public var actions: [String]
  public var resolution: UIActionResolution
  public var enabled: Bool
  /// Explains why the host considers this node executable without exposing coordinates.
  public var source: String?

  public init(
    id: String, title: String, role: String, actions: [String],
    resolution: UIActionResolution, enabled: Bool, source: String? = nil
  ) {
    self.id = id
    self.title = title
    self.role = role
    self.actions = actions
    self.resolution = resolution
    self.enabled = enabled
    self.source = source
  }
}

public struct ResolvedUIAction: Sendable {
  public var capability: UIActionCapability
  public var element: UIElement
  public var selector: ElementSelector
}

public enum UIActionCatalog {
  public static func capabilities(
    elements: [UIElement], fingerprint: ScreenFingerprint
  ) -> [UIActionCapability] {
    let rawCandidates = elements.filter { element in
      element.enabled && element.hittable && element.frame.width > 1 && element.frame.height > 1
        && (!supportedActions(for: element).isEmpty)
    }
    let controlsByTitle = Dictionary(
      grouping: rawCandidates.filter { !$0.availableActions.isEmpty },
      by: { element in
        normalized(element.label) ?? normalized(element.identifier) ?? ""
      })
    let candidates = rawCandidates.filter { element in
      guard element.availableActions.isEmpty else { return true }
      let title = normalized(element.label) ?? normalized(element.identifier)
      let centerX = element.frame.x + element.frame.width / 2
      let centerY = element.frame.y + element.frame.height / 2
      let duplicatesNativeControl = (controlsByTitle[title ?? ""] ?? []).contains { control in
        control.childPath != element.childPath
          && (normalized(control.label) == title || normalized(control.identifier) == title)
          && control.frame.x <= centerX && centerX <= control.frame.x + control.frame.width
          && control.frame.y <= centerY && centerY <= control.frame.y + control.frame.height
      }
      // A labelled accessibility wrapper around a real native control describes a region, not a
      // second executable target. Exposing both made agents tap quiz cards instead of their
      // nested "Start quiz" button. Standalone RN/Flutter accessibility containers remain valid.
      let containsNativeControl = rawCandidates.contains { control in
        guard control.childPath != element.childPath, !control.availableActions.isEmpty else {
          return false
        }
        let controlCenterX = control.frame.x + control.frame.width / 2
        let controlCenterY = control.frame.y + control.frame.height / 2
        return element.frame.x <= controlCenterX
          && controlCenterX <= element.frame.x + element.frame.width
          && element.frame.y <= controlCenterY
          && controlCenterY <= element.frame.y + element.frame.height
      }
      return !duplicatesNativeControl && !containsNativeControl
    }
    let identifierCounts = Dictionary(
      grouping: elements.compactMap { element in
        normalized(element.identifier).map { ($0, element) }
      }, by: \.0
    ).mapValues(\.count)
    let labelRoleCounts = Dictionary(
      grouping: elements.compactMap { element in
        normalized(element.label).map { ("\($0)|\(element.type)", element) }
      }, by: \.0
    ).mapValues(\.count)
    var seen = Set<String>()
    return candidates.compactMap { element -> (UIActionCapability, ElementFrame)? in
      let actions = supportedActions(for: element)
      let title =
        normalized(element.label) ?? normalized(element.identifier)
        ?? normalized(element.value) ?? element.type
      let identity = "\(element.childPath)|\(title)|\(element.type)"
      guard seen.insert(identity).inserted else { return nil }
      let semantic =
        normalized(element.identifier).map { identifierCounts[$0] == 1 } == true
        || normalized(element.label).map { labelRoleCounts["\($0)|\(element.type)"] == 1 } == true
      return (
        UIActionCapability(
          id: actionID(fingerprint: fingerprint, childPath: element.childPath), title: title,
          role: element.type, actions: actions, resolution: semantic ? .semantic : .screenBound,
          enabled: element.enabled,
          source: element.availableActions.isEmpty ? "accessibilityContainer" : "nativeControl"),
        element.frame
      )
    }.sorted {
      if $0.1.y == $1.1.y { return $0.1.x < $1.1.x }
      return $0.1.y < $1.1.y
    }.map(\.0)
  }

  public static func resolve(
    actionID: String, action: String, elements: [UIElement], fingerprint: ScreenFingerprint
  ) -> ResolvedUIAction? {
    guard
      let capability = capabilities(elements: elements, fingerprint: fingerprint)
        .first(where: { $0.id == actionID }), capability.actions.contains(action),
      let element = elements.first(where: {
        self.actionID(fingerprint: fingerprint, childPath: $0.childPath) == actionID
      })
    else { return nil }
    let selector: ElementSelector
    if let label = normalized(element.label),
      elements.filter({ $0.label == label && $0.type == element.type }).count == 1
    {
      selector = .labelType(label: label, type: element.type)
    } else if let identifier = normalized(element.identifier),
      elements.filter({ $0.identifier == identifier }).count == 1
    {
      selector = .accessibilityIdentifier(identifier)
    } else {
      selector = .hierarchyPath(element.xpath ?? element.childPath)
    }
    return .init(capability: capability, element: element, selector: selector)
  }

  private static func supportedActions(for element: UIElement) -> [String] {
    if !element.availableActions.isEmpty { return element.availableActions }
    if element.accessible == true
      && (normalized(element.label) != nil || normalized(element.identifier) != nil)
    {
      return ["tap"]
    }
    return []
  }

  public static func actionID(fingerprint: ScreenFingerprint, childPath: String) -> String {
    let digest = SHA256.hash(data: Data("\(fingerprint.digest)|\(childPath)".utf8))
      .prefix(10).map { String(format: "%02x", $0) }.joined()
    return "action_\(digest)"
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

/// A screen identity is intentionally stable across changing values so graph paths remain useful.
/// This stricter digest is only used around an interaction to prove that the app visibly reacted.
public struct UIInteractionStateFingerprint: Equatable, Sendable {
  public var digest: String

  public static func make(elements: [UIElement]) -> UIInteractionStateFingerprint {
    let state = elements.map { element in
      [
        element.type, element.identifier ?? "", element.label ?? "", element.value ?? "",
        element.enabled ? "enabled" : "disabled",
        element.selected ? "selected" : "unselected",
        element.focused == true ? "focused" : "unfocused",
        element.visible == false ? "hidden" : "visible",
        element.hittable ? "hittable" : "blocked",
        String(
          format: "%.1f,%.1f,%.1f,%.1f", element.frame.x, element.frame.y,
          element.frame.width, element.frame.height),
      ].joined(separator: "|")
    }.sorted().joined(separator: "\n")
    let digest = SHA256.hash(data: Data(state.utf8)).map { String(format: "%02x", $0) }.joined()
    return .init(digest: digest)
  }
}

public struct UIFlowProgress: Codable, Equatable, Sendable {
  public var current: Int
  public var total: Int
  public var sourceText: String

  public init(current: Int, total: Int, sourceText: String) {
    self.current = current
    self.total = total
    self.sourceText = sourceText
  }

  /// Reaching the last item is not the same as reaching a terminal result. A visible "10 of 10"
  /// quiz still needs its final answer; only explicit completion language is terminal evidence.
  public var isComplete: Bool {
    guard current >= total else { return false }
    let normalized = sourceText.lowercased()
    return normalized.contains("complete") || normalized.contains("finished")
  }
  public var remaining: Int { max(0, total - current) }
}

/// Finds explicit finite-flow progress exposed by the app, such as "1 of 10" or "3/5". The
/// host uses this as a completion guard; it never guesses progress from screen count or model text.
public enum UIFlowProgressDetector {
  private static let expression = try! NSRegularExpression(
    pattern: #"(?i)(?:\bquestion\s*)?(\d{1,4})\s*(?:out\s+of|of|/)\s*(\d{1,4})\b"#)

  public static func detect(in elements: [UIElement]) -> UIFlowProgress? {
    let candidates = elements.filter { element in
      guard element.visible != false else { return false }
      return ["StaticText", "ProgressIndicator", "PageIndicator"].contains(element.type)
        || (element.type == "Other" && element.accessible == true)
    }.flatMap { element in
      [element.label, element.value].compactMap { $0 }
    }.filter { text in
      text.count <= 64 && !text.localizedCaseInsensitiveContains(", tab")
    }.compactMap(parse)
    return candidates.sorted {
      if $0.total == $1.total { return $0.current > $1.current }
      return $0.total > $1.total
    }.first
  }

  private static func parse(_ text: String) -> UIFlowProgress? {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges == 3,
      let currentRange = Range(match.range(at: 1), in: text),
      let totalRange = Range(match.range(at: 2), in: text),
      let current = Int(text[currentRange]), let total = Int(text[totalRange]),
      current >= 0, total > 1, current <= total
    else { return nil }
    return .init(current: current, total: total, sourceText: text)
  }
}

public struct ScreenFingerprint: Codable, Hashable, Sendable {
  public var digest: String
  public var owningApplication: String
  public var isSystemState: Bool
  public init(digest: String, owningApplication: String, isSystemState: Bool = false) {
    self.digest = digest
    self.owningApplication = owningApplication
    self.isSystemState = isSystemState
  }

  public static func make(elements: [UIElement], modal: Bool, navigationTitle: String?)
    -> ScreenFingerprint
  {
    let app = elements.first?.owningApplication ?? "unknown"
    let stable =
      elements.map { element in
        [
          element.type, element.identifier ?? "", headingValue(element), element.childPath,
          element.enabled ? "enabled" : "disabled",
          element.selected ? "selected" : "unselected",
        ].joined(separator: "|")
      }.sorted().joined(separator: "\n") + "\nmodal=\(modal)\ntitle=\(navigationTitle ?? "")"
    let digest = SHA256.hash(data: Data(stable.utf8)).map { String(format: "%02x", $0) }.joined()
    return .init(
      digest: digest, owningApplication: app, isSystemState: app == "com.apple.springboard")
  }

  private static func headingValue(_ element: UIElement) -> String {
    ["NavigationBar", "Heading", "StaticText"].contains(element.type) ? (element.label ?? "") : ""
  }
}

public struct ScreenNode: Codable, Identifiable, Hashable, Sendable {
  public var id: String { fingerprint.digest }
  public var fingerprint: ScreenFingerprint
  public var name: String
  public var lastObservedAt: Date
  public var actions: [UIActionCapability]?
  public init(
    fingerprint: ScreenFingerprint, name: String, actions: [UIActionCapability] = []
  ) {
    self.fingerprint = fingerprint
    self.name = name
    self.lastObservedAt = Date()
    self.actions = actions
  }
}

public struct NavigationEdge: Codable, Identifiable, Hashable, Sendable {
  public let id: UUID
  public var from: ScreenFingerprint
  public var to: ScreenFingerprint
  public var selector: ElementSelector
  /// Recorded for intent-graph diagnostics. Only tap edges are eligible for automatic replay;
  /// text input is deliberately not persisted in the graph.
  public var action: String?
  /// Keeps iPhone and iPad validation separate while allowing legacy family-agnostic edges to
  /// remain reusable when no more specific edge exists.
  public var destinationFamily: String?
  public var preconditions: [String]
  public var successCount: Int
  public var failureCount: Int
  public var lastValidatedBuild: String
  public var stale: Bool
  public var confidence: Double {
    guard successCount + failureCount > 0 else { return 0 }
    return Double(successCount) / Double(successCount + failureCount)
  }
  public init(
    id: UUID = UUID(), from: ScreenFingerprint, to: ScreenFingerprint, selector: ElementSelector,
    action: String = "tap", destinationFamily: String? = nil, preconditions: [String] = [],
    lastValidatedBuild: String
  ) {
    self.id = id
    self.from = from
    self.to = to
    self.selector = selector
    self.action = action
    self.destinationFamily = destinationFamily
    self.preconditions = preconditions
    self.successCount = 1
    self.failureCount = 0
    self.lastValidatedBuild = lastValidatedBuild
    self.stale = false
  }
}

public struct AppGraphSnapshot: Codable, Sendable {
  public var nodes: [ScreenNode]
  public var edges: [NavigationEdge]

  public init(nodes: [ScreenNode] = [], edges: [NavigationEdge] = []) {
    self.nodes = nodes
    self.edges = edges
  }
}

public actor AppGraph {
  private var nodes: [String: ScreenNode] = [:]
  private var edges: [UUID: NavigationEdge] = [:]
  public init() {}

  public func replace(with snapshot: AppGraphSnapshot) {
    nodes = Dictionary(
      snapshot.nodes.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    edges = Dictionary(
      snapshot.edges.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
  }

  public func observeScreen(
    _ fingerprint: ScreenFingerprint, name: String = "Observed screen",
    actions: [UIActionCapability]
  ) {
    nodes[fingerprint.digest] = ScreenNode(
      fingerprint: fingerprint, name: name, actions: actions)
  }

  @discardableResult public func observe(
    from: ScreenFingerprint, to: ScreenFingerprint, selector: ElementSelector, build: String,
    action: String = "tap", destinationFamily: String? = nil,
    name: String = "Observed screen"
  ) -> NavigationEdge? {
    nodes[from.digest] = nodes[from.digest] ?? ScreenNode(fingerprint: from, name: name)
    nodes[to.digest] = ScreenNode(fingerprint: to, name: name)
    guard from != to else { return nil }
    if let existingID = edges.first(where: {
      $0.value.from == from && $0.value.to == to && $0.value.selector == selector
        && ($0.value.action ?? "tap") == action
        && $0.value.destinationFamily == destinationFamily
    })?.key {
      edges[existingID]!.successCount += 1
      edges[existingID]!.stale = false
      edges[existingID]!.lastValidatedBuild = build
      return edges[existingID]
    }
    let edge = NavigationEdge(
      from: from, to: to, selector: selector, action: action,
      destinationFamily: destinationFamily, lastValidatedBuild: build)
    edges[edge.id] = edge
    return edge
  }

  public func path(from start: ScreenFingerprint, to goal: ScreenFingerprint, build: String)
    -> [NavigationEdge]?
  {
    path(from: start, to: goal, build: build, destinationFamily: nil)
  }

  public func path(
    from start: ScreenFingerprint, to goal: ScreenFingerprint, build: String,
    destinationFamily: String?
  ) -> [NavigationEdge]?
  {
    if start == goal { return [] }
    var queue: [(ScreenFingerprint, [NavigationEdge])] = [(start, [])]
    var visited: Set<String> = [start.digest]
    while !queue.isEmpty {
      let (current, path) = queue.removeFirst()
      for edge in edges.values
      where edge.from == current && !edge.stale && edge.selector.deterministic
        && (edge.action ?? "tap") == "tap"
        && edge.lastValidatedBuild == build
        && (edge.destinationFamily == nil || edge.destinationFamily == destinationFamily)
      {
        if edge.to == goal { return path + [edge] }
        if visited.insert(edge.to.digest).inserted { queue.append((edge.to, path + [edge])) }
      }
    }
    return nil
  }

  public func recordFailure(_ edgeID: UUID) {
    edges[edgeID]?.failureCount += 1
    edges[edgeID]?.stale = true
  }
  public func snapshot() -> (nodes: [ScreenNode], edges: [NavigationEdge]) {
    (Array(nodes.values), Array(edges.values))
  }

  public func codableSnapshot() -> AppGraphSnapshot {
    .init(
      nodes: nodes.values.sorted { $0.id < $1.id },
      edges: edges.values.sorted { $0.id.uuidString < $1.id.uuidString })
  }
}
