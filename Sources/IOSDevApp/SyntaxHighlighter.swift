import Foundation

enum SyntaxLanguage: Equatable, Sendable {
  case swift
  case typescript
  case javascript
  case json
  case markdown
  case plainText

  init(fileURL: URL?) {
    guard let fileURL else {
      self = .plainText
      return
    }
    switch fileURL.pathExtension.lowercased() {
    case "swift": self = .swift
    case "ts", "tsx": self = .typescript
    case "js", "jsx", "mjs", "cjs": self = .javascript
    case "json", "jsonc": self = .json
    case "md", "markdown", "mdx": self = .markdown
    default: self = .plainText
    }
  }
}

enum SyntaxTokenKind: Equatable, Sendable {
  case keyword
  case type
  case string
  case number
  case comment
  case property
  case punctuation
  case heading
  case emphasis
  case link
  case code
}

struct SyntaxToken: Equatable, Sendable {
  var kind: SyntaxTokenKind
  var range: NSRange
}

enum SyntaxHighlighter {
  static let maximumHighlightedLength = 2_000_000

  static func tokens(in text: String, language: SyntaxLanguage) -> [SyntaxToken] {
    let source = text as NSString
    guard source.length <= maximumHighlightedLength else { return [] }
    switch language {
    case .swift:
      return cStyleTokens(in: source, language: .swift)
    case .typescript:
      return cStyleTokens(in: source, language: .typescript)
    case .javascript:
      return cStyleTokens(in: source, language: .javascript)
    case .json:
      return jsonTokens(in: source)
    case .markdown:
      return markdownTokens(in: source)
    case .plainText:
      return []
    }
  }

  private static let swiftKeywords: Set<String> = [
    "actor", "any", "as", "associatedtype", "async", "await", "borrowing", "break",
    "case", "catch", "class", "consume", "consuming", "continue", "convenience", "copy",
    "default", "defer", "deinit", "didSet", "distributed", "do", "dynamic", "else", "enum",
    "extension", "fallthrough", "fileprivate", "final", "for", "func", "get", "guard", "if",
    "import", "in", "indirect", "infix", "init", "inout", "internal", "isolated", "lazy", "let",
    "macro", "mutating", "nonisolated", "nonmutating", "open", "operator", "override", "package",
    "postfix", "precedencegroup", "prefix", "private", "protocol", "public", "repeat", "required",
    "rethrows", "return", "set", "some", "static", "struct", "subscript", "super", "switch",
    "throws", "try", "typealias", "unowned", "var", "weak", "where", "while", "willSet",
  ]

  private static let javascriptKeywords: Set<String> = [
    "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
    "declare", "default", "delete", "do", "else", "enum", "export", "extends", "finally", "for",
    "from", "function", "get", "if", "implements", "import", "in", "infer", "instanceof",
    "interface", "keyof", "let", "namespace", "new", "of", "package", "private", "protected",
    "public", "readonly", "return", "satisfies", "set", "static", "super", "switch", "throw",
    "try", "type", "typeof", "var", "void", "while", "with", "yield",
  ]

  private static let typeNames: Set<String> = [
    "Any", "Array", "Bool", "Boolean", "CGFloat", "Character", "Dictionary", "Double", "Error",
    "Float", "Int", "Never", "NSObject", "NSNumber", "Object", "Promise", "Result", "Set",
    "String", "UInt", "URL", "UUID", "Unknown", "Void", "any", "bigint", "boolean", "never",
    "number", "object", "string", "symbol", "unknown",
  ]

  private static let literalNames: Set<String> = [
    "false", "nil", "null", "self", "true", "undefined",
  ]

  private static func cStyleTokens(in source: NSString, language: SyntaxLanguage) -> [SyntaxToken] {
    let scanner = UTF16Scanner(source)
    var tokens: [SyntaxToken] = []
    var index = 0
    let keywords = language == .swift ? swiftKeywords : javascriptKeywords

    while index < scanner.length {
      let character = scanner.character(at: index)
      if isWhitespace(character) {
        index += 1
        continue
      }

      if scanner.matches("//", at: index) {
        let end = scanner.endOfLine(from: index)
        tokens.append(.init(kind: .comment, range: NSRange(location: index, length: end - index)))
        index = end
        continue
      }

      if scanner.matches("/*", at: index) {
        let start = index
        index += 2
        var depth = 1
        while index < scanner.length, depth > 0 {
          if scanner.matches("/*", at: index), language == .swift {
            depth += 1
            index += 2
          } else if scanner.matches("*/", at: index) {
            depth -= 1
            index += 2
          } else {
            index += 1
          }
        }
        tokens.append(.init(kind: .comment, range: NSRange(location: start, length: index - start)))
        continue
      }

      if language == .swift, character == ascii("#"),
        let end = scanner.endOfSwiftRawString(from: index)
      {
        tokens.append(.init(kind: .string, range: NSRange(location: index, length: end - index)))
        index = end
        continue
      }

      let acceptsSingleQuote = language == .javascript || language == .typescript
      if character == ascii("\"") || (acceptsSingleQuote && character == ascii("'"))
        || (acceptsSingleQuote && character == ascii("`"))
      {
        let end = scanner.endOfQuotedString(from: index, quote: character)
        tokens.append(.init(kind: .string, range: NSRange(location: index, length: end - index)))
        index = end
        continue
      }

      if isDigit(character) {
        let end = scanner.endOfNumber(from: index)
        tokens.append(.init(kind: .number, range: NSRange(location: index, length: end - index)))
        index = end
        continue
      }

      if isIdentifierStart(character) {
        let end = scanner.endOfIdentifier(from: index)
        let word = source.substring(with: NSRange(location: index, length: end - index))
        if keywords.contains(word) {
          tokens.append(.init(kind: .keyword, range: NSRange(location: index, length: end - index)))
        } else if literalNames.contains(word) {
          tokens.append(.init(kind: .number, range: NSRange(location: index, length: end - index)))
        } else if typeNames.contains(word) || characterIsUppercase(character) {
          tokens.append(.init(kind: .type, range: NSRange(location: index, length: end - index)))
        }
        index = end
        continue
      }

      if isPunctuation(character) {
        tokens.append(.init(kind: .punctuation, range: NSRange(location: index, length: 1)))
      }
      index += 1
    }
    return tokens
  }

  private static func jsonTokens(in source: NSString) -> [SyntaxToken] {
    let scanner = UTF16Scanner(source)
    var tokens: [SyntaxToken] = []
    var index = 0

    while index < scanner.length {
      let character = scanner.character(at: index)
      if isWhitespace(character) {
        index += 1
        continue
      }
      if scanner.matches("//", at: index) {
        let end = scanner.endOfLine(from: index)
        tokens.append(.init(kind: .comment, range: NSRange(location: index, length: end - index)))
        index = end
        continue
      }
      if scanner.matches("/*", at: index) {
        let start = index
        index += 2
        while index < scanner.length, !scanner.matches("*/", at: index) { index += 1 }
        index = min(scanner.length, index + 2)
        tokens.append(.init(kind: .comment, range: NSRange(location: start, length: index - start)))
        continue
      }
      if character == ascii("\"") {
        let end = scanner.endOfQuotedString(from: index, quote: character)
        let next = scanner.nextNonWhitespace(after: end)
        let kind: SyntaxTokenKind =
          next < scanner.length && scanner.character(at: next) == ascii(":")
          ? .property : .string
        tokens.append(.init(kind: kind, range: NSRange(location: index, length: end - index)))
        index = end
        continue
      }
      if character == ascii("-") || isDigit(character) {
        let end = scanner.endOfNumber(from: index)
        tokens.append(.init(kind: .number, range: NSRange(location: index, length: end - index)))
        index = max(index + 1, end)
        continue
      }
      if isIdentifierStart(character) {
        let end = scanner.endOfIdentifier(from: index)
        let word = source.substring(with: NSRange(location: index, length: end - index))
        if literalNames.contains(word) {
          tokens.append(.init(kind: .number, range: NSRange(location: index, length: end - index)))
        }
        index = end
        continue
      }
      if isPunctuation(character) {
        tokens.append(.init(kind: .punctuation, range: NSRange(location: index, length: 1)))
      }
      index += 1
    }
    return tokens
  }

  private static func markdownTokens(in source: NSString) -> [SyntaxToken] {
    let scanner = UTF16Scanner(source)
    var tokens: [SyntaxToken] = []
    var lineStart = 0
    var fenceCharacter: unichar?

    while lineStart < scanner.length {
      let lineEnd = scanner.endOfLine(from: lineStart)
      var contentEnd = lineEnd
      if contentEnd > lineStart, scanner.character(at: contentEnd - 1) == ascii("\r") {
        contentEnd -= 1
      }
      let first = scanner.nextNonWhitespace(after: lineStart, stoppingAt: contentEnd)
      let leadingSpaces = first - lineStart
      let detectedFence =
        leadingSpaces <= 3 && first < contentEnd
        ? markdownFenceCharacter(scanner, at: first, before: contentEnd) : nil

      if let activeFence = fenceCharacter {
        if detectedFence == activeFence {
          tokens.append(
            .init(kind: .keyword, range: NSRange(location: first, length: contentEnd - first)))
          fenceCharacter = nil
        } else if contentEnd > lineStart {
          tokens.append(
            .init(kind: .code, range: NSRange(location: lineStart, length: contentEnd - lineStart)))
        }
      } else if let detectedFence {
        tokens.append(
          .init(kind: .keyword, range: NSRange(location: first, length: contentEnd - first)))
        fenceCharacter = detectedFence
      } else if leadingSpaces <= 3, isMarkdownHeading(scanner, at: first, before: contentEnd) {
        tokens.append(
          .init(kind: .heading, range: NSRange(location: first, length: contentEnd - first)))
      } else {
        var inlineStart = first
        if first < contentEnd, scanner.character(at: first) == ascii(">") {
          tokens.append(.init(kind: .comment, range: NSRange(location: first, length: 1)))
          inlineStart = min(contentEnd, first + 1)
        } else if let markerEnd = markdownListMarkerEnd(scanner, at: first, before: contentEnd) {
          tokens.append(
            .init(kind: .punctuation, range: NSRange(location: first, length: markerEnd - first)))
          inlineStart = markerEnd
        }
        tokens.append(contentsOf: inlineMarkdownTokens(scanner, from: inlineStart, to: contentEnd))
      }

      lineStart = lineEnd < scanner.length ? lineEnd + 1 : scanner.length
    }
    return tokens
  }

  private static func inlineMarkdownTokens(_ scanner: UTF16Scanner, from start: Int, to end: Int)
    -> [SyntaxToken]
  {
    var tokens: [SyntaxToken] = []
    var index = start
    while index < end {
      if scanner.matches("<!--", at: index),
        let closing = scanner.range(of: "-->", from: index + 4, to: end)
      {
        let tokenEnd = NSMaxRange(closing)
        tokens.append(
          .init(kind: .comment, range: NSRange(location: index, length: tokenEnd - index)))
        index = tokenEnd
        continue
      }
      if scanner.character(at: index) == ascii("`") {
        var markerLength = 1
        while index + markerLength < end,
          scanner.character(at: index + markerLength) == ascii("`")
        {
          markerLength += 1
        }
        let marker = String(repeating: "`", count: markerLength)
        if let closing = scanner.range(of: marker, from: index + markerLength, to: end) {
          let tokenEnd = NSMaxRange(closing)
          tokens.append(
            .init(kind: .code, range: NSRange(location: index, length: tokenEnd - index)))
          index = tokenEnd
          continue
        }
      }
      if scanner.character(at: index) == ascii("["),
        let bracket = scanner.range(of: "](", from: index + 1, to: end),
        let closing = scanner.range(of: ")", from: NSMaxRange(bracket), to: end)
      {
        let tokenEnd = NSMaxRange(closing)
        tokens.append(.init(kind: .link, range: NSRange(location: index, length: tokenEnd - index)))
        index = tokenEnd
        continue
      }
      let character = scanner.character(at: index)
      if character == ascii("*") || character == ascii("_") {
        let doubled = index + 1 < end && scanner.character(at: index + 1) == character
        let marker =
          doubled
          ? String(repeating: Character(UnicodeScalar(character)!), count: 2)
          : String(Character(UnicodeScalar(character)!))
        let markerLength = doubled ? 2 : 1
        if let closing = scanner.range(of: marker, from: index + markerLength, to: end),
          closing.location > index + markerLength
        {
          let tokenEnd = NSMaxRange(closing)
          tokens.append(
            .init(kind: .emphasis, range: NSRange(location: index, length: tokenEnd - index)))
          index = tokenEnd
          continue
        }
      }
      index += 1
    }
    return tokens
  }

  private static func markdownFenceCharacter(
    _ scanner: UTF16Scanner, at index: Int, before end: Int
  ) -> unichar? {
    guard index + 2 < end else { return nil }
    let character = scanner.character(at: index)
    guard character == ascii("`") || character == ascii("~"),
      scanner.character(at: index + 1) == character,
      scanner.character(at: index + 2) == character
    else { return nil }
    return character
  }

  private static func isMarkdownHeading(_ scanner: UTF16Scanner, at index: Int, before end: Int)
    -> Bool
  {
    guard index < end, scanner.character(at: index) == ascii("#") else { return false }
    var cursor = index
    while cursor < end, scanner.character(at: cursor) == ascii("#"), cursor - index < 6 {
      cursor += 1
    }
    return cursor < end && isWhitespace(scanner.character(at: cursor))
  }

  private static func markdownListMarkerEnd(
    _ scanner: UTF16Scanner, at index: Int, before end: Int
  ) -> Int? {
    guard index < end else { return nil }
    let first = scanner.character(at: index)
    if first == ascii("-") || first == ascii("+") || first == ascii("*") {
      let markerEnd = index + 1
      return markerEnd < end && isWhitespace(scanner.character(at: markerEnd)) ? markerEnd : nil
    }
    guard isDigit(first) else { return nil }
    var cursor = index
    while cursor < end, isDigit(scanner.character(at: cursor)) { cursor += 1 }
    guard cursor < end,
      scanner.character(at: cursor) == ascii(".") || scanner.character(at: cursor) == ascii(")")
    else { return nil }
    let markerEnd = cursor + 1
    return markerEnd < end && isWhitespace(scanner.character(at: markerEnd)) ? markerEnd : nil
  }

  fileprivate static func ascii(_ character: Character) -> unichar {
    unichar(character.asciiValue!)
  }

  fileprivate static func isWhitespace(_ character: unichar) -> Bool {
    character == 9 || character == 10 || character == 13 || character == 32
  }

  fileprivate static func isDigit(_ character: unichar) -> Bool {
    character >= 48 && character <= 57
  }

  fileprivate static func isIdentifierStart(_ character: unichar) -> Bool {
    character == 36 || character == 95 || (character >= 65 && character <= 90)
      || (character >= 97 && character <= 122)
  }

  private static func characterIsUppercase(_ character: unichar) -> Bool {
    character >= 65 && character <= 90
  }

  private static func isPunctuation(_ character: unichar) -> Bool {
    switch character {
    case 40, 41, 44, 46, 58, 59, 91, 93, 123, 125: true
    default: false
    }
  }
}

private struct UTF16Scanner {
  let source: NSString
  var length: Int { source.length }

  init(_ source: NSString) {
    self.source = source
  }

  func character(at index: Int) -> unichar {
    source.character(at: index)
  }

  func matches(_ text: String, at index: Int) -> Bool {
    let candidateLength = (text as NSString).length
    guard index >= 0, index + candidateLength <= length else { return false }
    return source.compare(
      text, options: [], range: NSRange(location: index, length: candidateLength)) == .orderedSame
  }

  func range(of text: String, from start: Int, to end: Int) -> NSRange? {
    guard start <= end else { return nil }
    let result = source.range(
      of: text, options: [], range: NSRange(location: start, length: end - start))
    return result.location == NSNotFound ? nil : result
  }

  func endOfLine(from start: Int) -> Int {
    let newline = source.range(
      of: "\n", options: [], range: NSRange(location: start, length: length - start))
    return newline.location == NSNotFound ? length : newline.location
  }

  func nextNonWhitespace(after start: Int, stoppingAt limit: Int? = nil) -> Int {
    let end = limit ?? length
    var index = start
    while index < end, SyntaxHighlighter.isWhitespace(character(at: index)) { index += 1 }
    return index
  }

  func endOfIdentifier(from start: Int) -> Int {
    var index = start + 1
    while index < length {
      let character = character(at: index)
      guard SyntaxHighlighter.isIdentifierStart(character) || SyntaxHighlighter.isDigit(character)
      else { break }
      index += 1
    }
    return index
  }

  func endOfNumber(from start: Int) -> Int {
    var index = start
    if index < length, character(at: index) == SyntaxHighlighter.ascii("-") { index += 1 }

    if index + 1 < length, character(at: index) == SyntaxHighlighter.ascii("0") {
      let prefix = character(at: index + 1)
      if prefix == SyntaxHighlighter.ascii("x") || prefix == SyntaxHighlighter.ascii("X")
        || prefix == SyntaxHighlighter.ascii("b") || prefix == SyntaxHighlighter.ascii("B")
        || prefix == SyntaxHighlighter.ascii("o") || prefix == SyntaxHighlighter.ascii("O")
      {
        index += 2
        while index < length {
          let character = character(at: index)
          guard
            SyntaxHighlighter.isDigit(character)
              || (character >= 65 && character <= 70) || (character >= 97 && character <= 102)
              || character == SyntaxHighlighter.ascii("_")
          else { break }
          index += 1
        }
        return index
      }
    }

    while index < length,
      SyntaxHighlighter.isDigit(character(at: index))
        || character(at: index) == SyntaxHighlighter.ascii("_")
    {
      index += 1
    }
    if index < length, character(at: index) == SyntaxHighlighter.ascii(".") {
      index += 1
      while index < length,
        SyntaxHighlighter.isDigit(character(at: index))
          || character(at: index) == SyntaxHighlighter.ascii("_")
      {
        index += 1
      }
    }
    if index < length,
      character(at: index) == SyntaxHighlighter.ascii("e")
        || character(at: index) == SyntaxHighlighter.ascii("E")
    {
      index += 1
      if index < length,
        character(at: index) == SyntaxHighlighter.ascii("+")
          || character(at: index) == SyntaxHighlighter.ascii("-")
      {
        index += 1
      }
      while index < length,
        SyntaxHighlighter.isDigit(character(at: index))
          || character(at: index) == SyntaxHighlighter.ascii("_")
      {
        index += 1
      }
    }
    if index < length, character(at: index) == SyntaxHighlighter.ascii("n") {
      index += 1
    }
    return index
  }

  func endOfQuotedString(from start: Int, quote: unichar) -> Int {
    let triple = quote == SyntaxHighlighter.ascii("\"") && matches("\"\"\"", at: start)
    var index = start + (triple ? 3 : 1)
    while index < length {
      if triple, matches("\"\"\"", at: index) { return index + 3 }
      let character = character(at: index)
      if !triple, character == quote { return index + 1 }
      if character == SyntaxHighlighter.ascii("\\") {
        index = min(length, index + 2)
      } else {
        index += 1
      }
    }
    return length
  }

  func endOfSwiftRawString(from start: Int) -> Int? {
    var quoteIndex = start
    while quoteIndex < length, character(at: quoteIndex) == SyntaxHighlighter.ascii("#") {
      quoteIndex += 1
    }
    let hashCount = quoteIndex - start
    guard hashCount > 0, quoteIndex < length,
      character(at: quoteIndex) == SyntaxHighlighter.ascii("\"")
    else { return nil }
    let triple = matches("\"\"\"", at: quoteIndex)
    let quoteMarker = triple ? "\"\"\"" : "\""
    let closing = quoteMarker + String(repeating: "#", count: hashCount)
    let contentStart = quoteIndex + (triple ? 3 : 1)
    guard let range = range(of: closing, from: contentStart, to: length) else { return length }
    return NSMaxRange(range)
  }
}
