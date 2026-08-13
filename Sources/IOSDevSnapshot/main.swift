import AppKit
import IOSDevUI
import SwiftUI

@main
@MainActor
enum IOSDevSnapshotMain {
  static func main() throws {
    NSApplication.shared.appearance = NSAppearance(named: .aqua)
    let arguments = Array(CommandLine.arguments.dropFirst())
    let output =
      arguments.first.map(URL.init(fileURLWithPath:))
      ?? URL(fileURLWithPath: "/tmp/lys-workbench.png")
    let requestedSize = arguments.first(where: { $0.hasPrefix("--size=") })
      .map { String($0.dropFirst("--size=".count)) }
      .flatMap(parseSize)
    let size = requestedSize ?? CGSize(width: 1536, height: 1024)
    let model = AppModel()
    if arguments.contains("--settings") {
      model.loadSettingsPreview()
    } else if arguments.contains("--summary") {
      model.loadTaskSummaryPreview()
    } else if arguments.contains("--journey-recovery") {
      model.loadJourneyRecoveryPreview()
    } else if arguments.contains("--permission") {
      model.loadPermissionPreview()
    } else if arguments.contains("--building") {
      model.loadDesignBuildPreview()
    } else if arguments.contains("--failure") {
      model.loadDesignFailurePreview()
    } else if !arguments.contains("--empty") && !arguments.contains("--app-store-connection") {
      model.loadDesignPreview()
    }

    if arguments.contains("--code") {
      model.showSnapshotPage("code")
    } else if arguments.contains("--changes") {
      model.showSnapshotPage("changes")
    } else if arguments.contains("--deploy") {
      model.showSnapshotPage("deploy")
    } else if arguments.contains("--settings") {
      model.showSnapshotPage("settings")
    }
    if arguments.contains("--terminal") {
      model.showSnapshotWorkspaceTab("terminal")
    } else if arguments.contains("--logs") {
      model.showSnapshotWorkspaceTab("logs")
    } else if arguments.contains("--changes-tab") {
      model.showSnapshotWorkspaceTab("changes")
    } else if arguments.contains("--evidence") {
      model.showSnapshotWorkspaceTab("evidence")
    }
    let content: AnyView
    if arguments.contains("--app-store-connection") {
      content = AnyView(
        AppStoreConnectionSnapshotView()
          .environmentObject(model)
          .frame(width: size.width, height: size.height)
          .background(Color(nsColor: .windowBackgroundColor))
          .preferredColorScheme(.light)
      )
    } else {
      content = AnyView(
        WorkbenchView().environmentObject(model).frame(
          width: size.width, height: size.height
        )
        .preferredColorScheme(.light)
      )
    }
    let hosting = NSHostingView(rootView: content)
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
    else {
      throw CocoaError(.fileWriteUnknown)
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: output, options: .atomic)
    print(output.path)
  }

  private static func parseSize(_ value: String) -> CGSize? {
    let parts = value.split(separator: "x", maxSplits: 1).compactMap { Double($0) }
    guard parts.count == 2, parts[0] >= 1180, parts[1] >= 680 else { return nil }
    return CGSize(width: parts[0], height: parts[1])
  }
}
