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
  public var hittable: Bool
  public var frame: ElementFrame
  public var childPath: String
  public var owningApplication: String
  public var availableActions: [String]
  public init(
    type: String, identifier: String? = nil, label: String? = nil, value: String? = nil,
    enabled: Bool = true, selected: Bool = false, hittable: Bool = true, frame: ElementFrame,
    childPath: String, owningApplication: String, availableActions: [String] = []
  ) {
    self.type = type
    self.identifier = identifier
    self.label = label
    self.value = value
    self.enabled = enabled
    self.selected = selected
    self.hittable = hittable
    self.frame = frame
    self.childPath = childPath
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
        [element.type, element.identifier ?? "", headingValue(element), element.childPath].joined(
          separator: "|")
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
  public init(fingerprint: ScreenFingerprint, name: String) {
    self.fingerprint = fingerprint
    self.name = name
    self.lastObservedAt = Date()
  }
}

public struct NavigationEdge: Codable, Identifiable, Hashable, Sendable {
  public let id: UUID
  public var from: ScreenFingerprint
  public var to: ScreenFingerprint
  public var selector: ElementSelector
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
    preconditions: [String] = [], lastValidatedBuild: String
  ) {
    self.id = id
    self.from = from
    self.to = to
    self.selector = selector
    self.preconditions = preconditions
    self.successCount = 1
    self.failureCount = 0
    self.lastValidatedBuild = lastValidatedBuild
    self.stale = false
  }
}

public actor AppGraph {
  private var nodes: [String: ScreenNode] = [:]
  private var edges: [UUID: NavigationEdge] = [:]
  public init() {}

  @discardableResult public func observe(
    from: ScreenFingerprint, to: ScreenFingerprint, selector: ElementSelector, build: String,
    name: String = "Observed screen"
  ) -> NavigationEdge? {
    nodes[from.digest] = nodes[from.digest] ?? ScreenNode(fingerprint: from, name: name)
    nodes[to.digest] = ScreenNode(fingerprint: to, name: name)
    guard from != to else { return nil }
    if let existingID = edges.first(where: {
      $0.value.from == from && $0.value.to == to && $0.value.selector == selector
    })?.key {
      edges[existingID]!.successCount += 1
      edges[existingID]!.stale = false
      edges[existingID]!.lastValidatedBuild = build
      return edges[existingID]
    }
    let edge = NavigationEdge(from: from, to: to, selector: selector, lastValidatedBuild: build)
    edges[edge.id] = edge
    return edge
  }

  public func path(from start: ScreenFingerprint, to goal: ScreenFingerprint, build: String)
    -> [NavigationEdge]?
  {
    if start == goal { return [] }
    var queue: [(ScreenFingerprint, [NavigationEdge])] = [(start, [])]
    var visited: Set<String> = [start.digest]
    while !queue.isEmpty {
      let (current, path) = queue.removeFirst()
      for edge in edges.values
      where edge.from == current && !edge.stale && edge.selector.deterministic
        && edge.lastValidatedBuild == build
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
}
