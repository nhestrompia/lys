#if canImport(SwiftUI)
import SwiftUI

extension View {
  public func lysScreen(_ id: String, title: String, terminal: Bool = false) -> some View {
    let screen = LysScreen(id: id, title: title, terminal: terminal)
    Lys.registry.register(screen)
    return accessibilityElement(children: .contain)
      .accessibilityIdentifier("lys.screen.\(id)")
  }

  public func lysAction(
    _ id: String, title: String, on screen: String? = nil, resultsIn: String? = nil,
    kind: LysActionKind = .tap, risk: LysRisk = .reversible,
    parameters: [String: LysParameter]? = nil
  ) -> some View {
    Lys.registry.register(
      LysAction(
        id: id, title: title, route: screen, resultsIn: resultsIn, action: kind,
        parameters: parameters, risk: risk))
    return accessibilityIdentifier("lys.action.\(id)")
  }

  /// Exposes a small, non-sensitive observable value through the native accessibility surface.
  /// Prefer enums, booleans, counts, and status strings; never expose tokens or personal data.
  public func lysState(_ id: String, value: String) -> some View {
    accessibilityIdentifier("lys.state.\(id)").accessibilityValue(value)
  }
}
#endif
