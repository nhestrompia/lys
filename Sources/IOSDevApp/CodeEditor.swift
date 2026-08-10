import AppKit
import SwiftUI

@MainActor struct CodeEditor: NSViewRepresentable {
  @Binding var text: String
  var readOnly = false

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    let storage = NSTextStorage()
    let manager = NSLayoutManager()
    let container = NSTextContainer(
      containerSize: NSSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = false
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    let editor = NSTextView(frame: .zero, textContainer: container)
    editor.delegate = context.coordinator
    editor.isEditable = !readOnly
    editor.isRichText = false
    editor.allowsUndo = true
    editor.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    editor.textColor = NSColor(white: 0.9, alpha: 1)
    editor.backgroundColor = NSColor(red: 0.075, green: 0.085, blue: 0.1, alpha: 1)
    editor.insertionPointColor = NSColor.white
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.usesFindBar = true
    editor.isIncrementalSearchingEnabled = true
    editor.textContainerInset = NSSize(width: 42, height: 12)
    editor.string = text
    scroll.documentView = editor
    scroll.hasVerticalRuler = true
    scroll.rulersVisible = true
    scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, textView: editor)
    context.coordinator.editor = editor
    context.coordinator.highlight()
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let editor = scroll.documentView as? NSTextView else { return }
    if editor.string != text {
      editor.string = text
      context.coordinator.highlight()
    }
    editor.isEditable = !readOnly
  }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    weak var editor: NSTextView?
    init(text: Binding<String>) { _text = text }
    func textDidChange(_ notification: Notification) {
      guard let editor else { return }
      text = editor.string
      highlight()
      editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }
    func highlight() {
      guard let editor, let storage = editor.textStorage else { return }
      let range = NSRange(location: 0, length: storage.length)
      storage.beginEditing()
      storage.setAttributes(
        [
          .foregroundColor: NSColor(white: 0.86, alpha: 1),
          .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
        ], range: range)
      let source = storage.string as NSString
      for pattern in [
        "\\b(import|struct|class|enum|actor|func|let|var|if|else|guard|return|async|await|throws|public|private)\\b"
      ] {
        if let regex = try? NSRegularExpression(pattern: pattern) {
          regex.enumerateMatches(in: storage.string, range: range) { match, _, _ in
            if let match {
              storage.addAttribute(
                .foregroundColor, value: NSColor(red: 0.38, green: 0.69, blue: 0.94, alpha: 1),
                range: match.range)
            }
          }
        }
      }
      if let comments = try? NSRegularExpression(pattern: "//.*$", options: .anchorsMatchLines) {
        comments.enumerateMatches(in: storage.string, range: range) { match, _, _ in
          if let match {
            storage.addAttribute(
              .foregroundColor, value: NSColor(red: 0.38, green: 0.64, blue: 0.47, alpha: 1),
              range: match.range)
          }
        }
      }
      _ = source
      storage.endEditing()
    }
  }
}

@MainActor final class LineNumberRuler: NSRulerView {
  weak var textView: NSTextView?
  init(scrollView: NSScrollView, textView: NSTextView) {
    self.textView = textView
    super.init(scrollView: scrollView, orientation: .verticalRuler)
    clientView = textView
    ruleThickness = 38
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let textView, let layout = textView.layoutManager, let container = textView.textContainer
    else { return }
    NSColor(red: 0.075, green: 0.085, blue: 0.1, alpha: 1).setFill()
    rect.fill()
    let visible = textView.enclosingScrollView?.contentView.bounds ?? .zero
    let glyphRange = layout.glyphRange(forBoundingRect: visible, in: container)
    let text = textView.string as NSString
    var line = 1
    if glyphRange.location > 0 {
      line = text.substring(to: layout.characterIndexForGlyph(at: glyphRange.location)).reduce(1) {
        $1 == "\n" ? $0 + 1 : $0
      }
    }
    var glyph = glyphRange.location
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
      .foregroundColor: NSColor.secondaryLabelColor,
    ]
    while glyph < NSMaxRange(glyphRange) {
      let character = layout.characterIndexForGlyph(at: glyph)
      let lineRange = text.lineRange(for: NSRange(location: character, length: 0))
      let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
      let label = "\(line)" as NSString
      label.draw(
        at: NSPoint(
          x: ruleThickness - label.size(withAttributes: attributes).width - 7,
          y: rect.minY + textView.textContainerInset.height), withAttributes: attributes)
      glyph = layout.glyphIndexForCharacter(at: NSMaxRange(lineRange))
      if lineRange.length == 0 { break }
      line += 1
    }
  }
}
