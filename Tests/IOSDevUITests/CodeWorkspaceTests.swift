import AppKit
import Foundation
import Testing

@testable import IOSDevUI

@Test func fileTreeLoadsOnlyTheRequestedDirectory() throws {
  let root = FileManager.default.temporaryDirectory.appending(
    path: "lys-file-tree-\(UUID().uuidString)", directoryHint: .isDirectory)
  defer { try? FileManager.default.removeItem(at: root) }

  let source = root.appending(path: "Sources", directoryHint: .isDirectory)
  let nested = source.appending(path: "Nested", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
  try "struct App {}\n".write(
    to: source.appending(path: "App.swift"), atomically: true, encoding: .utf8)
  try "not loaded with the root\n".write(
    to: nested.appending(path: "Deep.swift"), atomically: true, encoding: .utf8)
  try FileManager.default.createDirectory(
    at: root.appending(path: ".build"), withIntermediateDirectories: true)
  try "hidden\n".write(
    to: root.appending(path: ".secret"), atomically: true, encoding: .utf8)

  let rootItems = try FileTreeLoader.contents(of: root)
  #expect(rootItems.map(\.name) == ["Sources"])
  #expect(rootItems[0].isDirectory)

  let sourceItems = try FileTreeLoader.contents(of: source)
  #expect(sourceItems.map(\.name) == ["App.swift", "Nested"])
  #expect(sourceItems.first(where: { $0.name == "App.swift" })?.isDirectory == false)
  #expect(sourceItems.first(where: { $0.name == "Nested" })?.isDirectory == true)
  #expect(!sourceItems.contains(where: { $0.name == "Deep.swift" }))
}

@Test func fileTreeDoesNotExpandDirectorySymlinks() throws {
  let root = FileManager.default.temporaryDirectory.appending(
    path: "lys-file-tree-symlink-\(UUID().uuidString)", directoryHint: .isDirectory)
  defer { try? FileManager.default.removeItem(at: root) }

  let directory = root.appending(path: "Directory", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(
    at: root.appending(path: "Directory Link"), withDestinationURL: directory)

  let items = try FileTreeLoader.contents(of: root)
  #expect(items.first(where: { $0.name == "Directory" })?.isDirectory == true)
  #expect(items.first(where: { $0.name == "Directory Link" })?.isDirectory == false)
}

@MainActor
@Test func lineNumberRulerRendersACompleteFileWithoutCyclingAtEOF() {
  let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
  scrollView.hasVerticalRuler = true
  scrollView.rulersVisible = true

  let textView = NSTextView(frame: scrollView.bounds)
  textView.string = (1...184).map { "line \($0)" }.joined(separator: "\n")
  textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
  textView.textColor = NSColor(white: 0.9, alpha: 1)
  textView.backgroundColor = NSColor(red: 0.075, green: 0.085, blue: 0.1, alpha: 1)
  textView.textContainerInset = NSSize(width: 42, height: 12)
  scrollView.documentView = textView

  let ruler = LineNumberRuler(scrollView: scrollView, textView: textView)
  ruler.frame = NSRect(x: 0, y: 0, width: 38, height: 500)
  scrollView.verticalRulerView = ruler
  ruler.reloadLineNumbers()

  let image = NSImage(size: NSSize(width: 38, height: 500))
  image.lockFocus()
  ruler.drawHashMarksAndLabels(in: ruler.bounds)
  image.unlockFocus()

  scrollView.layoutSubtreeIfNeeded()
  let preview = scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds)!
  scrollView.cacheDisplay(in: scrollView.bounds, to: preview)
  var brightTextPixels = 0
  for x in 70..<260 {
    for y in 400..<490 {
      guard let color = preview.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
      if color.redComponent > 0.5 { brightTextPixels += 1 }
    }
  }

  #expect(ruler.numberOfLines == 184)
  #expect(ruler.ruleThickness >= 38)
  #expect(brightTextPixels > 20)
}
