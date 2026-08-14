import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(
    Data("usage: create-installer-background.swift OUTPUT.png\n".utf8))
  exit(64)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let canvasSize = NSSize(width: 900, height: 560)
let image = NSImage(size: canvasSize)

image.lockFocus()

NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let title = "Lys"
let titleAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 36, weight: .bold),
  .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
]
let titleSize = title.size(withAttributes: titleAttributes)
title.draw(
  at: NSPoint(x: (canvasSize.width - titleSize.width) / 2, y: canvasSize.height - 88),
  withAttributes: titleAttributes)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 320, y: 270))
arrow.line(to: NSPoint(x: 580, y: 270))
arrow.move(to: NSPoint(x: 530, y: 315))
arrow.line(to: NSPoint(x: 580, y: 270))
arrow.line(to: NSPoint(x: 530, y: 225))
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.34, green: 0.47, blue: 0.82, alpha: 1).setStroke()
arrow.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiff),
  let png = bitmap.representation(using: .png, properties: [:])
else {
  FileHandle.standardError.write(Data("could not encode installer background\n".utf8))
  exit(1)
}

do {
  try png.write(to: destination)
} catch {
  FileHandle.standardError.write(Data("could not write installer background: \(error)\n".utf8))
  exit(1)
}
