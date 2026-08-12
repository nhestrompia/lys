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
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    editor.delegate = context.coordinator
    editor.isEditable = !readOnly
    editor.isRichText = false
    editor.allowsUndo = true
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.minSize = NSSize(width: 0, height: 0)
    editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.textContainer?.lineFragmentPadding = 0
    editor.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    editor.textColor = NSColor(white: 0.9, alpha: 1)
    editor.backgroundColor = NSColor(red: 0.075, green: 0.085, blue: 0.1, alpha: 1)
    editor.insertionPointColor = NSColor.white
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.usesFindBar = true
    editor.isIncrementalSearchingEnabled = true
    editor.textContainerInset = NSSize(width: 42, height: 12)
    editor.textStorage?.setAttributedString(
      NSAttributedString(
        string: text,
        attributes: [
          .foregroundColor: NSColor(white: 0.86, alpha: 1),
          .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
        ]))
    scroll.documentView = editor
    scroll.hasVerticalRuler = true
    scroll.rulersVisible = true
    scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, textView: editor)
    (scroll.verticalRulerView as? LineNumberRuler)?.reloadLineNumbers()
    context.coordinator.editor = editor
    context.coordinator.highlight()
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let editor = scroll.documentView as? NSTextView else { return }
    if editor.string != text {
      editor.string = text
      context.coordinator.highlight()
      (scroll.verticalRulerView as? LineNumberRuler)?.reloadLineNumbers()
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
      (editor.enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.reloadLineNumbers()
    }
    func highlight() {
    guard let editor, let storage = editor.textStorage else { return }
    let range = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    editor.textColor = NSColor(white: 0.86, alpha: 1)
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
  private var lineStarts = [0]
  var numberOfLines: Int { lineStarts.count }

  init(scrollView: NSScrollView, textView: NSTextView) {
    self.textView = textView
    super.init(scrollView: scrollView, orientation: .verticalRuler)
    clientView = textView
    ruleThickness = 38
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func reloadLineNumbers() {
    guard let textView else { return }
    let text = textView.string as NSString
    var starts = [0]
    var searchLocation = 0
    while searchLocation < text.length {
      let newline = text.range(
        of: "\n", options: [], range: NSRange(location: searchLocation, length: text.length - searchLocation))
      guard newline.location != NSNotFound else { break }
      searchLocation = NSMaxRange(newline)
      starts.append(searchLocation)
    }
    lineStarts = starts

    let digits = max(2, String(starts.count).count)
    let digitWidth = ("0" as NSString).size(
      withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)]
    ).width
    ruleThickness = max(38, ceil(CGFloat(digits) * digitWidth + 14))
    needsDisplay = true
  }

  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let textView, let layout = textView.layoutManager, let container = textView.textContainer
    else { return }
    NSColor(red: 0.075, green: 0.085, blue: 0.1, alpha: 1).setFill()
    // AppKit passes this hook a client-space dirty rect that can be as wide as the document.
    // Painting that rect lets the ruler cover the text view itself, so constrain the fill to the
    // ruler's own bounds.
    bounds.fill()
    let visible = textView.visibleRect
    let origin = textView.textContainerOrigin
    let visibleContainerRect = visible.offsetBy(dx: -origin.x, dy: -origin.y)
    let glyphRange = layout.glyphRange(forBoundingRect: visibleContainerRect, in: container)
    let firstCharacter =
      layout.numberOfGlyphs == 0
      ? 0
      : layout.characterIndexForGlyph(at: min(glyphRange.location, layout.numberOfGlyphs - 1))
    var lineIndex = lowerBound(for: firstCharacter)
    if lineIndex > 0 { lineIndex -= 1 }

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
      .foregroundColor: NSColor(white: 0.48, alpha: 1),
    ]

    while lineIndex < lineStarts.count {
      let character = lineStarts[lineIndex]
      let fragment: NSRect
      if character < textView.string.utf16.count, layout.numberOfGlyphs > 0 {
        let glyph = layout.glyphIndexForCharacter(at: character)
        fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
      } else if character == textView.string.utf16.count,
        layout.extraLineFragmentTextContainer != nil
      {
        fragment = layout.extraLineFragmentRect
      } else {
        break
      }

      let textY = fragment.minY + origin.y
      if textY > visible.maxY { break }
      if fragment.maxY + origin.y < visible.minY {
        lineIndex += 1
        continue
      }

      let label = "\(lineIndex + 1)" as NSString
      let labelSize = label.size(withAttributes: attributes)
      let rulerPoint = convert(NSPoint(x: 0, y: textY), from: textView)
      label.draw(
        at: NSPoint(
          x: ruleThickness - labelSize.width - 7,
          y: floor(rulerPoint.y + (fragment.height - labelSize.height) / 2)),
        withAttributes: attributes)
      lineIndex += 1
    }
  }

  private func lowerBound(for character: Int) -> Int {
    var lower = 0
    var upper = lineStarts.count
    while lower < upper {
      let middle = (lower + upper) / 2
      if lineStarts[middle] < character {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    return lower
  }
}
