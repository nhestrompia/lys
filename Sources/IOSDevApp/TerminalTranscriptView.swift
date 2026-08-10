import AppKit
import SwiftUI

@MainActor
struct TerminalTranscriptView: NSViewRepresentable {
  var entries: [TerminalEntry]

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.borderType = .noBorder
    scroll.drawsBackground = true
    scroll.backgroundColor = TerminalPalette.background
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = false
    scroll.scrollerStyle = .overlay

    let storage = NSTextStorage()
    let manager = NSLayoutManager()
    let container = NSTextContainer(
      containerSize: NSSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = false
    container.heightTracksTextView = false
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)

    let transcript = TerminalTextView(frame: .zero, textContainer: container)
    transcript.isEditable = false
    transcript.isSelectable = true
    transcript.isRichText = true
    transcript.importsGraphics = false
    transcript.drawsBackground = true
    transcript.backgroundColor = TerminalPalette.background
    transcript.textContainerInset = NSSize(width: 16, height: 12)
    transcript.textContainer?.lineFragmentPadding = 0
    transcript.isHorizontallyResizable = true
    transcript.isVerticallyResizable = true
    transcript.minSize = .zero
    transcript.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    transcript.usesFindBar = true
    transcript.isIncrementalSearchingEnabled = true
    transcript.setAccessibilityLabel("Terminal output")

    scroll.documentView = transcript
    context.coordinator.transcript = transcript
    render(entries, in: transcript, coordinator: context.coordinator, followOutput: true)
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let transcript = context.coordinator.transcript else { return }
    let visible = scroll.contentView.bounds
    let contentHeight = transcript.bounds.height
    let wasFollowingOutput = visible.maxY >= contentHeight - 24
    render(
      entries, in: transcript, coordinator: context.coordinator,
      followOutput: wasFollowingOutput)
  }

  private func render(
    _ entries: [TerminalEntry], in transcript: NSTextView, coordinator: Coordinator,
    followOutput: Bool
  ) {
    let rendered = Self.attributedTranscript(entries)
    if let storage = transcript.textStorage, storage.isEqual(to: rendered) { return }

    let selection = transcript.selectedRange()
    let hadSelection = selection.length > 0
    transcript.textStorage?.setAttributedString(rendered)

    let length = transcript.string.utf16.count
    let safeLocation = min(selection.location, length)
    let safeLength = min(selection.length, length - safeLocation)
    transcript.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
    transcript.layoutManager?.ensureLayout(for: transcript.textContainer!)

    if followOutput && !hadSelection {
      transcript.scrollRangeToVisible(NSRange(location: length, length: 0))
    }
  }

  private static func attributedTranscript(_ entries: [TerminalEntry]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 1.5
    paragraph.paragraphSpacing = 0
    let base: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
      .paragraphStyle: paragraph,
    ]

    if entries.isEmpty {
      result.append(
        NSAttributedString(
          string: "Run, Build, or prepare an Expo project to see commands and output.\n",
          attributes: base.merging([.foregroundColor: TerminalPalette.secondary]) { _, new in new })
      )
      return result
    }

    for (index, entry) in entries.enumerated() {
      if index > 0 { result.append(NSAttributedString(string: "\n")) }
      result.append(
        NSAttributedString(
          string: "\(entry.workingDirectory) % \(entry.command)\n",
          attributes: base.merging([.foregroundColor: commandColor(entry.state)]) { _, new in new })
      )
      let output = entry.output.isEmpty && entry.state == .running ? "Running…" : entry.output
      if !output.isEmpty {
        result.append(
          NSAttributedString(
            string: output.hasSuffix("\n") ? output : output + "\n",
            attributes: base.merging([.foregroundColor: TerminalPalette.output]) { _, new in new }))
      }
    }
    return result
  }

  private static func commandColor(_ state: TerminalEntry.State) -> NSColor {
    switch state {
    case .failed: NSColor(red: 1, green: 0.48, blue: 0.46, alpha: 1)
    case .succeeded: NSColor(red: 0.45, green: 0.86, blue: 0.52, alpha: 1)
    case .running: NSColor(red: 0.43, green: 0.68, blue: 1, alpha: 1)
    case .cancelled: TerminalPalette.secondary
    }
  }

  final class Coordinator {
    weak var transcript: NSTextView?
  }
}

private enum TerminalPalette {
  static let background = NSColor(red: 0.055, green: 0.06, blue: 0.07, alpha: 1)
  static let output = NSColor(white: 0.82, alpha: 1)
  static let secondary = NSColor(white: 0.58, alpha: 1)
}

private final class TerminalTextView: NSTextView {
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

  override func copy(_ sender: Any?) {
    let range = selectedRange()
    guard range.length > 0 else { return }
    let selected = (string as NSString).substring(with: range)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(selected, forType: .string)
  }
}
