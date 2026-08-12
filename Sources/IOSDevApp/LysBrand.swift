import AppKit
import SwiftUI

@MainActor
public enum LysBrand {
  public static func logoImage() -> NSImage? {
    loadImage(named: "lys-logo")
  }

  public static func applicationIconImage() -> NSImage? {
    loadImage(named: "lys-app-icon")
  }

  public static func installApplicationIcon() {
    guard let image = applicationIconImage() else { return }
    NSApplication.shared.applicationIconImage = image
  }

  private static func loadImage(named name: String) -> NSImage? {
    guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
      return nil
    }
    return NSImage(contentsOf: url)
  }
}

@MainActor
public struct LysLogoView: View {
  private let width: CGFloat
  private let height: CGFloat

  public init(width: CGFloat = 60, height: CGFloat = 42) {
    self.width = width
    self.height = height
  }

  public var body: some View {
    Group {
      if let image = LysBrand.logoImage() {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        Text("Lys")
          .font(.system(size: 20, weight: .bold))
      }
    }
    .frame(width: width, height: height)
    .accessibilityLabel("Lys logo")
  }
}
