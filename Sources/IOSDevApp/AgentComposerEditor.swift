import AppKit
import SwiftUI

@MainActor
struct AgentComposerEditor: NSViewRepresentable {
  @Binding var text: String
  var onSubmit: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.borderType = .noBorder
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true

    let editor = ActivatingTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 40))
    editor.delegate = context.coordinator
    editor.onSubmit = onSubmit
    editor.isEditable = true
    editor.isSelectable = true
    editor.isRichText = false
    editor.drawsBackground = false
    editor.allowsUndo = true
    editor.font = .systemFont(ofSize: 12)
    editor.textColor = .labelColor
    editor.insertionPointColor = .controlAccentColor
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.minSize = NSSize(width: 0, height: 34)
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.autoresizingMask = [.width]
    editor.textContainerInset = NSSize(width: 4, height: 6)
    editor.textContainer?.widthTracksTextView = true
    editor.textContainer?.lineFragmentPadding = 0
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.setAccessibilityLabel("Agent message")
    editor.string = text
    scroll.documentView = editor
    context.coordinator.editor = editor
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let editor = scroll.documentView as? ActivatingTextView else { return }
    editor.onSubmit = onSubmit
    if editor.string != text {
      editor.string = text
      editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    }
    editor.frame.size.width = scroll.contentSize.width
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    weak var editor: NSTextView?

    init(text: Binding<String>) { _text = text }

    func textDidChange(_ notification: Notification) {
      guard let editor else { return }
      text = editor.string
    }
  }
}

private final class ActivatingTextView: NSTextView {
  var onSubmit: (() -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func becomeFirstResponder() -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKey()
    return super.becomeFirstResponder()
  }

  override func mouseDown(with event: NSEvent) {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    super.mouseDown(with: event)
    window?.makeFirstResponder(self)
  }

  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.keyCode == 36, flags.contains(.command) {
      onSubmit?()
      return
    }
    super.keyDown(with: event)
  }
}
