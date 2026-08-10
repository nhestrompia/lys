// THESIS: The running iOS app is the center of work; agent intent and verification stay visibly adjacent instead of hiding in an IDE-dark dashboard.
// OWN-WORLD: Luminous macOS studio surfaces, quiet grouped lists, 14pt structural corners, system-blue action, and green only for machine-recorded success.
// STORY: Open a repository, delegate in isolation, watch the app, inspect fresh evidence, then review and apply or discard without losing context.
// FIRST VIEWPORT: Persistent navigation rail; task-focused Agent column; large device stage; Verify ledger; one bottom change-review bar with the primary action at right.
// FORM: Direct native reproduction of the user-supplied Operate reference, replacing the prior blueprint direction.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md

import AppKit
import IOSDevUI
import SwiftUI

@main
struct IOSDevWorkbenchApp: App {
  @StateObject private var model = AppModel()

  init() {
    // SwiftPM launches do not have an app bundle to establish this automatically. A regular
    // activation policy gives Operate a Dock presence and lets AppKit text views receive input.
    NSApplication.shared.setActivationPolicy(.regular)
    DispatchQueue.main.async {
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

  var body: some Scene {
    WindowGroup("iOS Development Workbench") {
      WorkbenchView().environmentObject(model).frame(minWidth: 1180, minHeight: 680)
        .preferredColorScheme(.light)
        .background(WindowViewportGuard())
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1440, height: 860)
    .commands {
      CommandGroup(after: .sidebar) {
        Divider()
        Button(model.isTerminalExpanded ? "Hide Terminal" : "Show Terminal") {
          model.toggleTerminal()
        }
        .keyboardShortcut("j", modifiers: .command)
      }
    }
  }
}

private struct WindowViewportGuard: NSViewRepresentable {
  final class Coordinator {
    var didActivateWindow = false
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    fitWindow(for: view, coordinator: context.coordinator)
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    fitWindow(for: view, coordinator: context.coordinator)
  }

  private func fitWindow(for view: NSView, coordinator: Coordinator) {
    DispatchQueue.main.async {
      guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
      let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
      var frame = window.frame
      frame.size.width = min(frame.width, visible.width)
      frame.size.height = min(frame.height, visible.height)
      frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
      frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
      if !window.frame.equalTo(frame) {
        window.setFrame(frame, display: true, animate: false)
      }
      if !coordinator.didActivateWindow {
        coordinator.didActivateWindow = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
      }
    }
  }
}
