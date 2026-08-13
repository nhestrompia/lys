import Foundation
import Testing

@testable import IOSDevUI

@Test func syntaxLanguageUsesTheSelectedFileExtension() {
  #expect(SyntaxLanguage(fileURL: URL(fileURLWithPath: "/tmp/App.swift")) == .swift)
  #expect(SyntaxLanguage(fileURL: URL(fileURLWithPath: "/tmp/App.tsx")) == .typescript)
  #expect(SyntaxLanguage(fileURL: URL(fileURLWithPath: "/tmp/metro.config.js")) == .javascript)
  #expect(SyntaxLanguage(fileURL: URL(fileURLWithPath: "/tmp/package.json")) == .json)
  #expect(SyntaxLanguage(fileURL: URL(fileURLWithPath: "/tmp/README.md")) == .markdown)
  #expect(SyntaxLanguage(fileURL: URL(fileURLWithPath: "/tmp/Podfile")) == .plainText)
}

@Test func jsonKeepsKeywordsInsideStringsAndDistinguishesKeys() {
  let source = #"{"@react-native/async-storage":"2.1.2","enabled":true,"count":42}"#
  let tokens = SyntaxHighlighter.tokens(in: source, language: .json)

  #expect(
    lexemes(.property, in: source, tokens: tokens) == [
      #""@react-native/async-storage""#, #""enabled""#, #""count""#,
    ])
  #expect(lexemes(.string, in: source, tokens: tokens) == [#""2.1.2""#])
  #expect(lexemes(.number, in: source, tokens: tokens) == ["true", "42"])
  #expect(lexemes(.keyword, in: source, tokens: tokens).isEmpty)
  expectValidNonOverlappingRanges(tokens, source: source)
}

@Test func swiftDoesNotHighlightKeywordsInsideStringsOrComments() {
  let source = ##"let value = #"return async"# // await and throw"##
  let tokens = SyntaxHighlighter.tokens(in: source, language: .swift)

  #expect(lexemes(.keyword, in: source, tokens: tokens) == ["let"])
  #expect(lexemes(.string, in: source, tokens: tokens) == [##"#"return async"#"##])
  #expect(lexemes(.comment, in: source, tokens: tokens) == ["// await and throw"])
  expectValidNonOverlappingRanges(tokens, source: source)
}

@Test func typescriptHighlightsLanguageStructureWithoutColoringStringContents() {
  let source = #"const result: Promise<string> = await load("async") // done"#
  let tokens = SyntaxHighlighter.tokens(in: source, language: .typescript)

  #expect(lexemes(.keyword, in: source, tokens: tokens) == ["const", "await"])
  #expect(lexemes(.type, in: source, tokens: tokens) == ["Promise", "string"])
  #expect(lexemes(.string, in: source, tokens: tokens) == [#""async""#])
  #expect(lexemes(.comment, in: source, tokens: tokens) == ["// done"])
  expectValidNonOverlappingRanges(tokens, source: source)
}

@Test func markdownProvidesMinimalStructureForCommonAuthoringSyntax() {
  let source = """
    # Setup
    Use **bold**, `npm start`, and [the docs](https://example.com).
    > Keep this visible.
    ```swift
    let ready = true
    ```
    """
  let tokens = SyntaxHighlighter.tokens(in: source, language: .markdown)

  #expect(lexemes(.heading, in: source, tokens: tokens) == ["# Setup"])
  #expect(lexemes(.emphasis, in: source, tokens: tokens) == ["**bold**"])
  #expect(lexemes(.link, in: source, tokens: tokens) == ["[the docs](https://example.com)"])
  #expect(lexemes(.code, in: source, tokens: tokens) == ["`npm start`", "let ready = true"])
  #expect(lexemes(.keyword, in: source, tokens: tokens) == ["```swift", "```"])
  #expect(lexemes(.comment, in: source, tokens: tokens) == [">"])
  expectValidNonOverlappingRanges(tokens, source: source)
}

@Test func oversizedFilesFallBackToPlainText() {
  let source = String(repeating: "a", count: SyntaxHighlighter.maximumHighlightedLength + 1)
  #expect(SyntaxHighlighter.tokens(in: source, language: .typescript).isEmpty)
}

private func lexemes(_ kind: SyntaxTokenKind, in source: String, tokens: [SyntaxToken]) -> [String]
{
  let text = source as NSString
  return tokens.filter { $0.kind == kind }.map { text.substring(with: $0.range) }
}

private func expectValidNonOverlappingRanges(_ tokens: [SyntaxToken], source: String) {
  let length = (source as NSString).length
  var previousEnd = 0
  for token in tokens {
    #expect(token.range.location >= previousEnd)
    #expect(token.range.length > 0)
    #expect(NSMaxRange(token.range) <= length)
    previousEnd = NSMaxRange(token.range)
  }
}
