#if canImport(UIKit)
import UIKit

extension UIView {
  /// Registers a UIKit screen without turning its container into one accessibility element. Root
  /// views receive a tiny semantic marker so their buttons remain independently actionable.
  @discardableResult
  public func lysScreen(_ id: String, title: String, terminal: Bool = false) -> Self {
    Lys.registry.register(LysScreen(id: id, title: title, terminal: terminal))
    let identifier = "lys.screen.\(id)"
    if self is UIControl || self is UILabel || self is UIImageView {
      isAccessibilityElement = true
      accessibilityIdentifier = identifier
    } else if !subviews.contains(where: { $0.accessibilityIdentifier == identifier }) {
      let marker = UIView(frame: .zero)
      marker.translatesAutoresizingMaskIntoConstraints = false
      marker.isAccessibilityElement = true
      marker.isUserInteractionEnabled = false
      marker.accessibilityIdentifier = identifier
      marker.accessibilityLabel = title
      addSubview(marker)
      NSLayoutConstraint.activate([
        marker.leadingAnchor.constraint(equalTo: leadingAnchor),
        marker.topAnchor.constraint(equalTo: topAnchor),
        marker.widthAnchor.constraint(equalToConstant: 1),
        marker.heightAnchor.constraint(equalToConstant: 1),
      ])
    }
    return self
  }

  /// Registers and identifies an actionable UIKit control.
  @discardableResult
  public func lysAction(
    _ id: String, title: String, on screen: String? = nil, resultsIn: String? = nil,
    kind: LysActionKind = .tap, risk: LysRisk = .reversible,
    parameters: [String: LysParameter]? = nil
  ) -> Self {
    Lys.registry.register(
      LysAction(
        id: id, title: title, route: screen, resultsIn: resultsIn, action: kind,
        parameters: parameters, risk: risk))
    isAccessibilityElement = true
    accessibilityIdentifier = "lys.action.\(id)"
    return self
  }

  /// Exposes a small, non-sensitive state value through accessibility.
  @discardableResult
  public func lysState(_ id: String, value: String) -> Self {
    isAccessibilityElement = true
    accessibilityIdentifier = "lys.state.\(id)"
    accessibilityValue = value
    return self
  }
}
#endif
