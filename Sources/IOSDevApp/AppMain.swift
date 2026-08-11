// THESIS: The running iOS app is the center of work; agent intent and verification stay visibly adjacent instead of hiding in an IDE-dark dashboard.
// OWN-WORLD: Luminous macOS studio surfaces, quiet grouped lists, 14pt structural corners, system-blue action, and green only for machine-recorded success.
// STORY: Open a repository, delegate in isolation, watch the app, inspect fresh evidence, then review and apply or discard without losing context.
// FIRST VIEWPORT: Persistent navigation rail; task-focused Agent column; large device stage; Verify ledger; one bottom change-review bar with the primary action at right.
// FORM: Direct native reproduction of the user-supplied reference, replacing the prior blueprint direction.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md

import IOSDevCore
import SwiftUI

@main
struct IOSDevWorkbenchApp: App {
  @StateObject private var model = AppModel()
  var body: some Scene {
    WindowGroup("Lys") {
      WorkbenchView().environmentObject(model).frame(minWidth: 1180, minHeight: 680)
        .preferredColorScheme(.light)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1536, height: 1024)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("Open Repository…") { model.chooseRepository() }.keyboardShortcut("o")
      }
      CommandGroup(after: .sidebar) {
        Button(model.isEvidenceWorkspaceOpen ? "Hide Evidence" : "Show Evidence") {
          model.toggleEvidenceWorkspace()
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
      }
    }
  }
}
