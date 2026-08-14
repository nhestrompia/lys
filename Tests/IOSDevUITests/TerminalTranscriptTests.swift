import AppKit
import Testing

@testable import IOSDevUI

@MainActor
@Test func terminalUsesPersistentDarkScrollbars() {
  let scroll = NSScrollView()
  TerminalScrollConfiguration.apply(to: scroll)

  #expect(scroll.scrollerStyle == .legacy)
  #expect(!scroll.autohidesScrollers)
  #expect(scroll.hasVerticalScroller)
  #expect(!scroll.hasHorizontalScroller)
  #expect(scroll.verticalScroller is TerminalScroller)
  #expect(scroll.horizontalScroller == nil)

  let track = TerminalScroller.trackColor.usingColorSpace(.sRGB)
  let knob = TerminalScroller.knobColor.usingColorSpace(.sRGB)
  #expect((track?.redComponent ?? 1) < 0.25)
  #expect((knob?.redComponent ?? 0) > (track?.redComponent ?? 1))
}
