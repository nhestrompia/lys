import AppKit
import SwiftUI

@MainActor struct SyntaxHighlightedText: View {
  let text: String
  let language: SyntaxLanguage

  var body: some View {
    highlightedText
      .font(.system(size: 11, weight: .regular, design: .monospaced))
      .foregroundStyle(Color(nsColor: .labelColor).opacity(0.84))
  }

  private var highlightedText: Text {
    let source = text.isEmpty ? " " : text
    let nsSource = source as NSString
    let fullRange = NSRange(location: 0, length: nsSource.length)
    let tokens = SyntaxHighlighter.tokens(in: source, language: language)
    var result = Text("")
    var cursor = 0

    for token in tokens {
      let range = NSIntersectionRange(token.range, fullRange)
      guard range.length > 0 else { continue }
      if range.location > cursor {
        let fragment = Text(nsSource.substring(with: NSRange(
          location: cursor, length: range.location - cursor)))
        result = Text("\(result)\(fragment)")
      }
      let fragment = Text(nsSource.substring(with: range))
        .foregroundStyle(CodeEditorTheme.color(for: token.kind))
      result = Text("\(result)\(fragment)")
      cursor = max(cursor, NSMaxRange(range))
    }

    if cursor < nsSource.length {
      let fragment = Text(nsSource.substring(with: NSRange(
        location: cursor, length: nsSource.length - cursor)))
      result = Text("\(result)\(fragment)")
    }
    return result
  }
}

@MainActor struct CodeEditor: NSViewRepresentable {
  @Binding var text: String
  var fileURL: URL?
  var readOnly = false

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, language: SyntaxLanguage(fileURL: fileURL))
  }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    CodeEditorScrollConfiguration.apply(to: scroll)
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    editor.delegate = context.coordinator
    editor.isEditable = !readOnly
    editor.isRichText = false
    editor.allowsUndo = true
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.minSize = NSSize(width: 0, height: 0)
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.textContainer?.lineFragmentPadding = 0
    editor.font = CodeEditorTheme.baseFont
    editor.textColor = CodeEditorTheme.baseText
    editor.backgroundColor = CodeEditorTheme.background
    editor.selectedTextAttributes = CodeEditorTheme.selectionAttributes
    editor.insertionPointColor = NSColor.systemBlue
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.usesFindBar = true
    editor.isIncrementalSearchingEnabled = true
    editor.textContainerInset = NSSize(width: 22, height: 16)
    editor.textStorage?.setAttributedString(
      NSAttributedString(
        string: text,
        attributes: CodeEditorTheme.baseAttributes))
    editor.typingAttributes = CodeEditorTheme.baseAttributes
    scroll.documentView = editor
    scroll.hasVerticalRuler = true
    scroll.rulersVisible = true
    scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, textView: editor)
    (scroll.verticalRulerView as? LineNumberRuler)?.reloadLineNumbers()
    context.coordinator.editor = editor
    context.coordinator.highlightImmediately()
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let editor = scroll.documentView as? NSTextView else { return }
    let languageChanged = context.coordinator.setLanguage(SyntaxLanguage(fileURL: fileURL))
    if editor.string != text {
      editor.string = text
      (scroll.verticalRulerView as? LineNumberRuler)?.reloadLineNumbers()
      context.coordinator.highlightImmediately()
    } else if languageChanged {
      context.coordinator.highlightImmediately()
    }
    editor.isEditable = !readOnly
  }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    weak var editor: NSTextView?
    private var language: SyntaxLanguage
    private var highlightRevision = 0
    private var highlightTask: Task<Void, Never>?

    init(text: Binding<String>, language: SyntaxLanguage) {
      _text = text
      self.language = language
    }

    func setLanguage(_ language: SyntaxLanguage) -> Bool {
      guard self.language != language else { return false }
      self.language = language
      return true
    }

    func textDidChange(_ notification: Notification) {
      guard let editor else { return }
      text = editor.string
      scheduleHighlight()
      (editor.enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.reloadLineNumbers()
    }

    func highlightImmediately() {
      guard let editor else { return }
      highlightTask?.cancel()
      highlightRevision += 1
      let source = editor.string
      applyBaseAttributes()

      if (source as NSString).length <= 250_000 {
        apply(SyntaxHighlighter.tokens(in: source, language: language), to: source)
      } else {
        scheduleHighlight(delayMilliseconds: 0)
      }
    }

    private func scheduleHighlight(delayMilliseconds: Int = 55) {
      guard let editor else { return }
      highlightTask?.cancel()
      highlightRevision += 1
      let revision = highlightRevision
      let source = editor.string
      let language = language

      highlightTask = Task { [weak self] in
        if delayMilliseconds > 0 {
          try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        }
        guard !Task.isCancelled else { return }
        let tokens = await Task.detached(priority: .userInitiated) {
          SyntaxHighlighter.tokens(in: source, language: language)
        }.value
        guard !Task.isCancelled, let self, self.highlightRevision == revision else { return }
        self.apply(tokens, to: source)
      }
    }

    private func applyBaseAttributes() {
      guard let editor, let storage = editor.textStorage else { return }
      let range = NSRange(location: 0, length: storage.length)
      storage.beginEditing()
      storage.setAttributes(CodeEditorTheme.baseAttributes, range: range)
      storage.endEditing()
      editor.typingAttributes = CodeEditorTheme.baseAttributes
    }

    private func apply(_ tokens: [SyntaxToken], to source: String) {
      guard let editor, editor.string == source, let storage = editor.textStorage else { return }
      let fullRange = NSRange(location: 0, length: storage.length)
      storage.beginEditing()
      storage.setAttributes(CodeEditorTheme.baseAttributes, range: fullRange)
      for token in tokens where NSMaxRange(token.range) <= storage.length {
        storage.addAttributes(CodeEditorTheme.attributes(for: token.kind), range: token.range)
      }
      storage.endEditing()
      editor.typingAttributes = CodeEditorTheme.baseAttributes
    }
  }
}

@MainActor enum CodeEditorScrollConfiguration {
  static func apply(to scroll: NSScrollView) {
    // Overlay scrollers follow the system's auto-hide preference. The editor needs a stable,
    // discoverable position indicator, so reserve a narrow persistent gutter instead.
    scroll.scrollerStyle = .legacy
    scroll.autohidesScrollers = false
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.verticalScroller = CodeEditorScroller()
    scroll.horizontalScroller = CodeEditorScroller()
  }
}

@MainActor enum CodeEditorTheme {
  static let background = NSColor.white
  static let baseText = NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
  static let baseFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
  static let headingFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
  static let selectionBackground = NSColor(red: 0.84, green: 0.91, blue: 1, alpha: 1)
  static let selectionText = NSColor(red: 0.08, green: 0.16, blue: 0.3, alpha: 1)
  static let baseAttributes: [NSAttributedString.Key: Any] = [
    .foregroundColor: baseText,
    .font: baseFont,
  ]
  static let selectionAttributes: [NSAttributedString.Key: Any] = [
    .backgroundColor: selectionBackground,
    .foregroundColor: selectionText,
  ]

  static func attributes(for kind: SyntaxTokenKind) -> [NSAttributedString.Key: Any] {
    let color: NSColor
    let font: NSFont
    switch kind {
    case .keyword:
      color = NSColor(red: 0.30, green: 0.22, blue: 0.66, alpha: 1)
      font = baseFont
    case .type:
      color = NSColor(red: 0.50, green: 0.79, blue: 0.76, alpha: 1)
      font = baseFont
    case .string, .code:
      color = NSColor(red: 0.70, green: 0.26, blue: 0.16, alpha: 1)
      font = baseFont
    case .number:
      color = NSColor(red: 0.10, green: 0.48, blue: 0.62, alpha: 1)
      font = baseFont
    case .comment:
      color = NSColor(red: 0.30, green: 0.48, blue: 0.34, alpha: 1)
      font = baseFont
    case .property:
      color = NSColor(red: 0.05, green: 0.37, blue: 0.72, alpha: 1)
      font = baseFont
    case .punctuation:
      color = NSColor(red: 0.38, green: 0.41, blue: 0.46, alpha: 1)
      font = baseFont
    case .heading:
      color = NSColor(red: 0.12, green: 0.32, blue: 0.68, alpha: 1)
      font = headingFont
    case .emphasis:
      color = NSColor(red: 0.58, green: 0.24, blue: 0.62, alpha: 1)
      font = baseFont
    case .link:
      color = NSColor(red: 0.04, green: 0.39, blue: 0.82, alpha: 1)
      font = baseFont
    }
    return [.foregroundColor: color, .font: font]
  }

  static func color(for kind: SyntaxTokenKind) -> Color {
    guard let color = attributes(for: kind)[.foregroundColor] as? NSColor else {
      return Color(nsColor: baseText)
    }
    return Color(nsColor: color)
  }
}

@MainActor final class CodeEditorScroller: NSScroller {
  static let knobColor = NSColor(red: 0.62, green: 0.65, blue: 0.70, alpha: 0.96)
  static let trackColor = NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)

  override class var isCompatibleWithOverlayScrollers: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    Self.trackColor.setFill()
    bounds.fill()
    drawKnob()
  }

  override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
    Self.trackColor.setFill()
    slotRect.fill()
  }

  override func drawKnob() {
    var knob = rect(for: .knob)
    guard !knob.isEmpty else { return }

    if bounds.height >= bounds.width {
      knob = knob.insetBy(dx: 3, dy: 1)
    } else {
      knob = knob.insetBy(dx: 1, dy: 3)
    }
    guard knob.width > 0, knob.height > 0 else { return }

    Self.knobColor.setFill()
    NSBezierPath(
      roundedRect: knob,
      xRadius: min(knob.width, knob.height) / 2,
      yRadius: min(knob.width, knob.height) / 2
    ).fill()
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
        of: "\n", options: [],
        range: NSRange(location: searchLocation, length: text.length - searchLocation))
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
    NSColor.white.setFill()
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
