import AppKit
import Combine
import CoreGraphics
import Darwin
import QuartzCore
import SwiftUI

enum SimulatorLivePhase: Equatable {
  case idle
  case connecting
  case streaming
  case setupRequired(String)
  case failed(String)

  var label: String {
    switch self {
    case .idle: "Live view idle"
    case .connecting: "Connecting live view…"
    case .streaming: "Live"
    case .setupRequired: "Live input setup required"
    case .failed: "Live view unavailable"
    }
  }
}

enum SimulatorInputPhase: Equatable {
  case idle
  case connecting
  case ready
  case fallback(String)

  var label: String {
    switch self {
    case .idle: "Input idle"
    case .connecting: "Connecting touch…"
    case .ready: "Live"
    case .fallback: "Live · semantic input"
    }
  }

  var detail: String? {
    if case .fallback(let detail) = self { return detail }
    return nil
  }
}

private struct SimulatorFrameGeometry: Sendable {
  let width: Int
  let height: Int
  let bytesPerRow: Int

  var frameByteCount: Int { bytesPerRow * height }
  var size: CGSize { CGSize(width: width, height: height) }
}

private final class SimulatorFrame: @unchecked Sendable {
  let image: CGImage
  init(image: CGImage) { self.image = image }
}

/// Owns a continuous CoreSimulator framebuffer stream and a persistent HID connection. Frames
/// never enter SwiftUI state: a single CALayer is updated in place so the rest of the workbench
/// does not re-render 30 times per second.
final class SimulatorLiveSession: ObservableObject, @unchecked Sendable {
  @Published private(set) var phase: SimulatorLivePhase = .idle
  @Published private(set) var inputPhase: SimulatorInputPhase = .idle
  @Published private(set) var measuredFPS = 0

  private let frameQueue = DispatchQueue(
    label: "com.operate.simulator.frames", qos: .userInteractive)
  private weak var renderer: SimulatorLiveNSView?
  private var streamProcess: Process?
  private var streamOutput: Pipe?
  private var streamErrors: Pipe?
  private var streamID = UUID()
  private var buffer = Data()
  private var geometry: SimulatorFrameGeometry?
  private var frameCount = 0
  private var frameWindowStarted = DispatchTime.now().uptimeNanoseconds
  private let hid = SimulatorHIDBrokerClient()

  var isStreaming: Bool { phase == .streaming }
  var isInputReady: Bool { inputPhase == .ready }
  static var helperAvailable: Bool { axeExecutable() != nil }

  @MainActor
  func attach(_ view: SimulatorLiveNSView) {
    renderer = view
    if let geometry { view.updateFrameSize(geometry.size) }
  }

  @MainActor
  func detach(_ view: SimulatorLiveNSView) {
    if renderer === view { renderer = nil }
  }

  @MainActor
  func start(
    udid: String, nativePixelWidth: Int, nativePixelHeight: Int,
    developerDirectory: URL?
  ) {
    stop()
    guard let axe = Self.axeExecutable() else {
      publish(
        .setupRequired(
          "Install the pinned AXe HID helper to enable the continuous Simulator stream."))
      return
    }
    let displayScale = nativePixelWidth >= 1_000 ? 3 : 2
    let width = max(1, nativePixelWidth / displayScale)
    let height = max(1, nativePixelHeight / displayScale)
    let bytesPerRow = ((width * 4 + 63) / 64) * 64
    let geometry = SimulatorFrameGeometry(
      width: width, height: height, bytesPerRow: bytesPerRow)
    let scale = 1.0 / Double(displayScale)
    let identifier = UUID()
    streamID = identifier
    self.geometry = geometry
    hid.updatePointSize(geometry.size)
    buffer.removeAll(keepingCapacity: true)
    frameCount = 0
    frameWindowStarted = DispatchTime.now().uptimeNanoseconds
    renderer?.updateFrameSize(geometry.size)
    publish(.connecting)
    publishInput(.connecting)

    let output = Pipe()
    let errors = Pipe()
    let process = Process()
    process.executableURL = axe
    process.arguments = [
      "stream-video", "--udid", udid, "--format", "bgra", "--fps", "30",
      "--scale", String(scale),
    ]
    process.standardOutput = output
    process.standardError = errors
    process.environment = ProcessInfo.processInfo.environment.merging(
      developerDirectory.map { ["DEVELOPER_DIR": $0.path] } ?? [:]
    ) { _, selected in selected }
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      self?.frameQueue.async { [weak self] in
        self?.consume(data, geometry: geometry, streamID: identifier)
      }
    }
    errors.fileHandleForReading.readabilityHandler = { handle in
      _ = handle.availableData
    }
    process.terminationHandler = { [weak self] process in
      guard let self, self.streamID == identifier else { return }
      if process.terminationStatus != 0 {
        self.publish(.failed("The CoreSimulator framebuffer stream stopped unexpectedly."))
      }
    }
    do {
      try process.run()
      streamProcess = process
      streamOutput = output
      streamErrors = errors
      hid.prepare(udid: udid, axe: axe, developerDirectory: developerDirectory) {
        [weak self] failure in
        guard self?.streamID == identifier else { return }
        if let failure {
          self?.publishInput(.fallback(failure))
        } else {
          self?.publishInput(.ready)
        }
      }
    } catch {
      publish(.failed(error.localizedDescription))
    }
  }

  @MainActor
  func stop() {
    streamID = UUID()
    streamOutput?.fileHandleForReading.readabilityHandler = nil
    streamErrors?.fileHandleForReading.readabilityHandler = nil
    if streamProcess?.isRunning == true { streamProcess?.interrupt() }
    streamProcess = nil
    streamOutput = nil
    streamErrors = nil
    hid.stop()
    frameQueue.async { [weak self] in self?.buffer.removeAll(keepingCapacity: false) }
    measuredFPS = 0
    phase = .idle
    inputPhase = .idle
  }

  func touchDown(at normalizedPoint: CGPoint) {
    hid.send(kind: .down, at: normalizedPoint)
  }

  func tap(at normalizedPoint: CGPoint) {
    hid.sendTap(at: normalizedPoint)
  }

  func touchMoved(to normalizedPoint: CGPoint) {
    hid.sendLatestMove(to: normalizedPoint)
  }

  func touchUp(at normalizedPoint: CGPoint) {
    hid.send(kind: .up, at: normalizedPoint)
  }

  func scroll(deltaX: CGFloat, deltaY: CGFloat) {
    hid.sendScroll(deltaX: deltaX, deltaY: deltaY)
  }

  func sendKeyboardEvent(_ event: NSEvent) {
    guard
      let simulator = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.iphonesimulator"
      ).first,
      let down = CGEvent(
        keyboardEventSource: nil, virtualKey: CGKeyCode(event.keyCode), keyDown: true),
      let up = CGEvent(
        keyboardEventSource: nil, virtualKey: CGKeyCode(event.keyCode), keyDown: false)
    else { return }
    let flags = event.cgEvent?.flags ?? []
    down.flags = flags
    up.flags = flags
    down.postToPid(simulator.processIdentifier)
    up.postToPid(simulator.processIdentifier)
  }

  private func consume(
    _ data: Data, geometry: SimulatorFrameGeometry, streamID identifier: UUID
  ) {
    guard streamID == identifier else { return }
    buffer.append(data)
    let completeFrames = buffer.count / geometry.frameByteCount
    guard completeFrames > 0 else { return }
    let lastOffset = (completeFrames - 1) * geometry.frameByteCount
    let frameData = buffer.subdata(
      in: lastOffset..<(lastOffset + geometry.frameByteCount))
    buffer.removeSubrange(0..<(completeFrames * geometry.frameByteCount))
    guard
      let provider = CGDataProvider(data: frameData as CFData),
      let image = CGImage(
        width: geometry.width, height: geometry.height, bitsPerComponent: 8,
        bitsPerPixel: 32, bytesPerRow: geometry.bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
          .union(.byteOrder32Little),
        provider: provider, decode: nil, shouldInterpolate: true,
        intent: .defaultIntent)
    else { return }
    frameCount += completeFrames
    let now = DispatchTime.now().uptimeNanoseconds
    if now - frameWindowStarted >= 1_000_000_000 {
      let elapsed = Double(now - frameWindowStarted) / 1_000_000_000
      let fps = Int((Double(frameCount) / elapsed).rounded())
      frameCount = 0
      frameWindowStarted = now
      DispatchQueue.main.async { [weak self] in self?.measuredFPS = fps }
    }
    let frame = SimulatorFrame(image: image)
    DispatchQueue.main.async { [weak self, frame] in
      guard let self, self.streamID == identifier else { return }
      self.renderer?.present(frame.image)
      if self.phase != .streaming { self.phase = .streaming }
    }
  }

  private func publish(_ newPhase: SimulatorLivePhase) {
    if Thread.isMainThread {
      phase = newPhase
    } else {
      DispatchQueue.main.async { [weak self] in self?.phase = newPhase }
    }
  }

  private func publishInput(_ newPhase: SimulatorInputPhase) {
    if Thread.isMainThread {
      inputPhase = newPhase
    } else {
      DispatchQueue.main.async { [weak self] in self?.inputPhase = newPhase }
    }
  }

  private static func axeExecutable() -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates = [
      URL(fileURLWithPath: "/opt/homebrew/bin/axe"),
      URL(fileURLWithPath: "/usr/local/bin/axe"),
      home.appending(path: ".local/bin/axe"),
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }
}

struct SimulatorLiveSurface: NSViewRepresentable {
  @ObservedObject var session: SimulatorLiveSession
  let onTap: (CGPoint) -> Void
  let onSwipe: (CGPoint, CGPoint) -> Void

  func makeNSView(context: Context) -> SimulatorLiveNSView {
    let view = SimulatorLiveNSView(session: session, onTap: onTap, onSwipe: onSwipe)
    session.attach(view)
    return view
  }

  func updateNSView(_ view: SimulatorLiveNSView, context: Context) {
    if view.session !== session {
      view.session?.detach(view)
      view.session = session
      session.attach(view)
    }
    view.onTap = onTap
    view.onSwipe = onSwipe
  }

  static func dismantleNSView(_ view: SimulatorLiveNSView, coordinator: Void) {
    view.session?.detach(view)
  }
}

final class SimulatorLiveNSView: NSView {
  weak var session: SimulatorLiveSession?
  var onTap: (CGPoint) -> Void
  var onSwipe: (CGPoint, CGPoint) -> Void
  private let displayLayer = CALayer()
  private var frameSize = CGSize(width: 402, height: 874)
  private var pointerStart: CGPoint?
  private var directTouchActive = false
  private var directDragStarted = false
  private var fallbackScrollDelta = CGSize.zero
  private var lastFallbackScrollAt: TimeInterval = 0

  init(
    session: SimulatorLiveSession,
    onTap: @escaping (CGPoint) -> Void,
    onSwipe: @escaping (CGPoint, CGPoint) -> Void
  ) {
    self.session = session
    self.onTap = onTap
    self.onSwipe = onSwipe
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    displayLayer.contentsGravity = .resizeAspect
    displayLayer.magnificationFilter = .linear
    displayLayer.minificationFilter = .trilinear
    layer?.addSublayer(displayLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    displayLayer.frame = bounds
    CATransaction.commit()
  }

  func updateFrameSize(_ size: CGSize) { frameSize = size }

  func present(_ image: CGImage) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    displayLayer.contents = image
    CATransaction.commit()
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    guard let point = normalizedPoint(for: event) else { return }
    pointerStart = point
    directTouchActive = session?.isInputReady == true
    directDragStarted = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard directTouchActive else { return }
    guard let point = normalizedPoint(for: event), let start = pointerStart else { return }
    if !directDragStarted {
      let distance = abs(point.x - start.x) + abs(point.y - start.y)
      guard distance >= 0.015 else { return }
      directDragStarted = true
      session?.touchDown(at: start)
    }
    session?.touchMoved(to: point)
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      pointerStart = nil
      directTouchActive = false
      directDragStarted = false
    }
    guard let point = normalizedPoint(for: event), let start = pointerStart else { return }
    if directTouchActive {
      if directDragStarted {
        session?.touchUp(at: point)
      } else {
        // A click is one broker transaction. Splitting down/up over independent sockets could
        // leave CoreSimulator with no coherent tap even though both writes succeeded.
        session?.tap(at: point)
      }
      return
    }
    let distance = abs(point.x - start.x) + abs(point.y - start.y)
    if distance < 0.025 {
      onTap(point)
    } else {
      onSwipe(start, point)
    }
  }

  override func scrollWheel(with event: NSEvent) {
    if session?.isInputReady == true {
      session?.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
      return
    }
    fallbackScrollDelta.width += event.scrollingDeltaX
    fallbackScrollDelta.height += event.scrollingDeltaY
    let phasesEnded = event.phase.contains(.ended) || event.momentumPhase.contains(.ended)
    dispatchFallbackScrollIfNeeded(force: phasesEnded)
  }

  override func keyDown(with event: NSEvent) { session?.sendKeyboardEvent(event) }

  private func normalizedPoint(for event: NSEvent) -> CGPoint? {
    let point = convert(event.locationInWindow, from: nil)
    let content = aspectFitRect(contentSize: frameSize, in: bounds)
    guard content.contains(point), content.width > 0, content.height > 0 else { return nil }
    return CGPoint(
      x: min(max((point.x - content.minX) / content.width, 0), 1),
      y: min(max(1 - ((point.y - content.minY) / content.height), 0), 1))
  }

  private func dispatchFallbackScrollIfNeeded(force: Bool) {
    let delta = fallbackScrollDelta
    let magnitude = max(abs(delta.width), abs(delta.height))
    let now = ProcessInfo.processInfo.systemUptime
    guard magnitude >= 14, force || now - lastFallbackScrollAt >= 0.22 else { return }
    fallbackScrollDelta = .zero
    lastFallbackScrollAt = now
    let vertical = abs(delta.height) >= abs(delta.width)
    let selectedDelta = vertical ? delta.height : delta.width
    let amount = min(max(selectedDelta / 240, -0.36), 0.36)
    let start = CGPoint(x: 0.5, y: 0.5)
    let end = CGPoint(
      x: vertical ? 0.5 : min(max(0.5 - amount, 0.12), 0.88),
      y: vertical ? min(max(0.5 - amount, 0.12), 0.88) : 0.5)
    onSwipe(start, end)
  }

  private func aspectFitRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
    let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
    let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    return CGRect(
      x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
      width: size.width, height: size.height)
  }
}

private enum SimulatorHIDTouchKind: String, Codable, Sendable {
  case down
  case up
  case delay
}

private struct SimulatorHIDPrimitive: Codable, Sendable {
  let kind: SimulatorHIDTouchKind
  let x: Double?
  let y: Double?
  let duration: Double?
}

private struct SimulatorHIDRequest: Codable, Sendable {
  let primitives: [SimulatorHIDPrimitive]
}

private struct SimulatorHIDHandshake: Codable { let ready: Bool }
private struct SimulatorHIDResponse: Codable { let error: String? }

private final class SimulatorHIDBrokerClient: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.operate.simulator.hid", qos: .userInteractive)
  private let pendingLock = NSLock()
  private var udid: String?
  private var pointSize = CGSize(width: 402, height: 874)
  private var endpoint: String?
  private var brokerProcess: Process?
  private var pendingMove: CGPoint?
  private var movePumpRunning = false
  private var pendingScroll = CGSize.zero
  private var scrollPumpRunning = false
  private var failureHandler: (@Sendable (String?) -> Void)?

  func prepare(
    udid: String, axe: URL, developerDirectory: URL?,
    completion: @escaping @Sendable (String?) -> Void
  ) {
    queue.async { [weak self] in
      guard let self else { return }
      self.failureHandler = completion
      self.udid = udid
      self.endpoint = Self.endpoint(udid: udid, developerDirectory: developerDirectory)
      guard let endpoint = self.endpoint else {
        completion(
          "Direct touch could not resolve the selected Xcode runtime; using semantic input.")
        return
      }
      if (try? self.verifyReady(path: endpoint, retry: false)) == true {
        completion(nil)
        return
      }
      let process = Process()
      process.executableURL = axe
      process.arguments = ["hid-broker", "--udid", udid]
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      process.environment = ProcessInfo.processInfo.environment.merging(
        ["AXE_HID_STABILIZATION_MS": "0"].merging(
          developerDirectory.map { ["DEVELOPER_DIR": $0.path] } ?? [:]
        ) { _, selected in selected }
      ) { _, selected in selected }
      do {
        try process.run()
        self.brokerProcess = process
        guard try self.verifyReady(path: endpoint, retry: true) else {
          throw CocoaError(.coderReadCorrupt)
        }
        completion(nil)
      } catch {
        completion(
          "Direct touch did not start: \(error.localizedDescription). Using semantic input.")
      }
    }
  }

  func updatePointSize(_ size: CGSize) {
    queue.async { [weak self] in self?.pointSize = size }
  }

  func send(kind: SimulatorHIDTouchKind, at normalizedPoint: CGPoint) {
    queue.async { [weak self] in
      guard let self else { return }
      let point = self.devicePoint(normalizedPoint)
      do {
        try self.send([.init(kind: kind, x: point.x, y: point.y, duration: nil)])
      } catch {
        self.reportFailure(error)
      }
    }
  }

  func sendTap(at normalizedPoint: CGPoint) {
    queue.async { [weak self] in
      guard let self else { return }
      let point = self.devicePoint(normalizedPoint)
      do {
        try self.send([
          .init(kind: .down, x: point.x, y: point.y, duration: nil),
          .init(kind: .delay, x: nil, y: nil, duration: 0.04),
          .init(kind: .up, x: point.x, y: point.y, duration: nil),
        ])
      } catch {
        self.reportFailure(error)
      }
    }
  }

  /// Mouse-drag events can arrive faster than CoreSimulator accepts socket transactions. Keep
  /// only the newest position so pointer input can never accumulate a seconds-long queue.
  func sendLatestMove(to normalizedPoint: CGPoint) {
    pendingLock.lock()
    pendingMove = normalizedPoint
    let shouldStart = !movePumpRunning
    movePumpRunning = true
    pendingLock.unlock()
    guard shouldStart else { return }
    queue.async { [weak self] in self?.drainLatestMoves() }
  }

  func sendScroll(deltaX: CGFloat, deltaY: CGFloat) {
    pendingLock.lock()
    pendingScroll.width += deltaX
    pendingScroll.height += deltaY
    let shouldStart = !scrollPumpRunning
    scrollPumpRunning = true
    pendingLock.unlock()
    guard shouldStart else { return }
    queue.async { [weak self] in self?.drainScroll() }
  }

  private func drainLatestMoves() {
    while true {
      pendingLock.lock()
      guard let point = pendingMove else {
        movePumpRunning = false
        pendingLock.unlock()
        return
      }
      pendingMove = nil
      pendingLock.unlock()
      let device = devicePoint(point)
      do {
        try send([.init(kind: .down, x: device.x, y: device.y, duration: nil)])
      } catch {
        reportFailure(error)
        return
      }
    }
  }

  private func drainScroll() {
    while true {
      pendingLock.lock()
      let delta = pendingScroll
      pendingScroll = .zero
      if delta == .zero {
        scrollPumpRunning = false
        pendingLock.unlock()
        return
      }
      pendingLock.unlock()
      let vertical = abs(delta.height) >= abs(delta.width)
      let selectedDelta = vertical ? delta.height : delta.width
      let amount = min(max(Double(selectedDelta) / 240, -0.36), 0.36)
      let start = CGPoint(x: 0.5, y: 0.5)
      let end = CGPoint(
        x: vertical ? 0.5 : min(max(0.5 - amount, 0.12), 0.88),
        y: vertical ? min(max(0.5 - amount, 0.12), 0.88) : 0.5)
      let startPoint = self.devicePoint(start)
      let endPoint = self.devicePoint(end)
      var primitives: [SimulatorHIDPrimitive] = [
        .init(kind: .down, x: startPoint.x, y: startPoint.y, duration: nil)
      ]
      for step in 1...6 {
        let progress = Double(step) / 6
        primitives.append(.init(kind: .delay, x: nil, y: nil, duration: 0.008))
        primitives.append(
          .init(
            kind: .down,
            x: startPoint.x + (endPoint.x - startPoint.x) * progress,
            y: startPoint.y + (endPoint.y - startPoint.y) * progress,
            duration: nil))
      }
      primitives.append(.init(kind: .up, x: endPoint.x, y: endPoint.y, duration: nil))
      do {
        try send(primitives)
      } catch {
        reportFailure(error)
        return
      }
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self else { return }
      if self.brokerProcess?.isRunning == true { self.brokerProcess?.interrupt() }
      self.brokerProcess = nil
      self.udid = nil
      self.endpoint = nil
      self.failureHandler = nil
      self.pendingLock.lock()
      self.pendingMove = nil
      self.pendingScroll = .zero
      self.pendingLock.unlock()
    }
  }

  private func devicePoint(_ normalized: CGPoint) -> (x: Double, y: Double) {
    (
      Double(min(max(normalized.x, 0), 1) * pointSize.width),
      Double(min(max(normalized.y, 0), 1) * pointSize.height)
    )
  }

  private func send(_ primitives: [SimulatorHIDPrimitive]) throws {
    guard let endpoint else { throw CocoaError(.fileNoSuchFile) }
    let descriptor = try connectWithRetry(path: endpoint)
    defer { Darwin.close(descriptor) }
    try Self.configureSocketTimeouts(descriptor, readMilliseconds: 2_000, writeMilliseconds: 2_000)
    let handshake = try JSONDecoder().decode(
      SimulatorHIDHandshake.self, from: readLine(descriptor))
    guard handshake.ready else { throw CocoaError(.coderReadCorrupt) }
    try Self.configureReceiveTimeout(descriptor, milliseconds: 30_000)
    var payload = try JSONEncoder().encode(SimulatorHIDRequest(primitives: primitives))
    payload.append(0x0A)
    try writeAll(payload, descriptor: descriptor)
    let response = try JSONDecoder().decode(
      SimulatorHIDResponse.self, from: readLine(descriptor))
    if let error = response.error {
      throw NSError(domain: "SimulatorHID", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
    }
  }

  private func verifyReady(path: String, retry: Bool) throws -> Bool {
    let descriptor = try (retry ? connectWithRetry(path: path) : Self.connect(path: path))
    defer { Darwin.close(descriptor) }
    try Self.configureReceiveTimeout(descriptor, milliseconds: 2_000)
    let handshake = try JSONDecoder().decode(
      SimulatorHIDHandshake.self, from: readLine(descriptor))
    return handshake.ready
  }

  private func reportFailure(_ error: Error) {
    failureHandler?(
      "Direct touch disconnected: \(error.localizedDescription). Using semantic input.")
  }

  private func connectWithRetry(path: String) throws -> Int32 {
    var lastError: Error = CocoaError(.fileNoSuchFile)
    for _ in 0..<80 {
      do { return try Self.connect(path: path) } catch {
        lastError = error
        usleep(25_000)
      }
    }
    throw lastError
  }

  private func readLine(_ descriptor: Int32) throws -> Data {
    var result = Data()
    var byte: UInt8 = 0
    while result.count < 65_536 {
      let count = Darwin.read(descriptor, &byte, 1)
      guard count > 0 else { throw CocoaError(.fileReadUnknown) }
      if byte == 0x0A { return result }
      result.append(byte)
    }
    throw CocoaError(.fileReadTooLarge)
  }

  private func writeAll(_ data: Data, descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
        offset += count
      }
    }
  }

  private static func connect(path: String) throws -> Int32 {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
      Darwin.close(descriptor)
      throw CocoaError(.fileReadInvalidFileName)
    }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    let connected = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else {
      let code = errno
      Darwin.close(descriptor)
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
    return descriptor
  }

  private static func configureSocketTimeouts(
    _ descriptor: Int32, readMilliseconds: Int, writeMilliseconds: Int
  ) throws {
    try configureReceiveTimeout(descriptor, milliseconds: readMilliseconds)
    var writeTimeout = socketTimeout(milliseconds: writeMilliseconds)
    guard
      setsockopt(
        descriptor, SOL_SOCKET, SO_SNDTIMEO, &writeTimeout,
        socklen_t(MemoryLayout<timeval>.size)) == 0
    else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
  }

  private static func configureReceiveTimeout(_ descriptor: Int32, milliseconds: Int) throws {
    var readTimeout = socketTimeout(milliseconds: milliseconds)
    guard
      setsockopt(
        descriptor, SOL_SOCKET, SO_RCVTIMEO, &readTimeout,
        socklen_t(MemoryLayout<timeval>.size)) == 0
    else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
  }

  private static func socketTimeout(milliseconds: Int) -> timeval {
    timeval(
      tv_sec: milliseconds / 1_000,
      tv_usec: Int32((milliseconds % 1_000) * 1_000))
  }

  private static func endpoint(udid: String, developerDirectory: URL?) -> String? {
    guard let developerDirectory else { return nil }
    var temporary = NSTemporaryDirectory()
    if temporary.hasPrefix("/private/var/") { temporary.removeFirst("/private".count) }
    let root = URL(fileURLWithPath: temporary).appending(path: "axe-hid-\(getuid())")
    let developer = developerDirectory.standardizedFileURL.resolvingSymlinksInPath().path
    return root.appending(
      path: "\(fnv1a64(udid))-\(fnv1a64(developer))-v2.sock"
    ).path
  }

  private static func fnv1a64(_ value: String) -> String {
    let hash = value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
      (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }
}
