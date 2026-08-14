import Foundation

struct WDANormalizedPoint: Equatable, Sendable {
  let x: Double
  let y: Double

  init(x: Double, y: Double) {
    self.x = min(max(x, 0), 1)
    self.y = min(max(y, 0), 1)
  }

  func scaled(width: Double, height: Double) -> (x: Double, y: Double) {
    (x * max(width, 0), y * max(height, 0))
  }
}

public actor WDAController {
  private let stateRoot: URL
  private var process: Process?
  private var processOutputHandle: FileHandle?
  private var activeUDID: String?
  private var sessionID: String?
  private var sessionBundleID: String?
  private var cachedWindowSize: (width: Double, height: Double)?
  private let baseURL = URL(string: "http://127.0.0.1:8100")!

  public init(stateRoot: URL) { self.stateRoot = stateRoot }

  public func stop() async {
    let child = process
    processOutputHandle?.readabilityHandler = nil
    processOutputHandle = nil
    if child?.isRunning == true { child?.interrupt() }
    if let child {
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while child.isRunning && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(50))
      }
      if child.isRunning { child.terminate() }
    }
    process = nil
    activeUDID = nil
    sessionID = nil
    sessionBundleID = nil
    cachedWindowSize = nil
  }

  public func prepare(
    udid: String, runtime: String, bundleID: String, preflight: ToolchainPreflight
  ) async throws {
    try await ensureSession(
      udid: udid, runtime: runtime, bundleID: bundleID, preflight: preflight)
  }

  public func snapshot(
    udid: String, runtime: String, bundleID: String, preflight: ToolchainPreflight
  ) async throws -> [UIElement] {
    try await ensureSession(
      udid: udid, runtime: runtime, bundleID: bundleID, preflight: preflight)
    guard let sessionID else { throw RPCError(code: -32077, message: "WDA session is missing") }
    let response = try await request(path: "/session/\(sessionID)/source")
    guard let xml = response["value"] as? String else {
      throw RPCError(code: -32077, message: "WDA returned an invalid hierarchy")
    }
    return try WDAHierarchyParser.parse(xml)
  }

  public func perform(
    udid: String, runtime: String, bundleID: String, identifier: String? = nil,
    label: String? = nil, type: String? = nil,
    action: String, text: String?, preflight: ToolchainPreflight
  ) async throws {
    try await ensureSession(
      udid: udid, runtime: runtime, bundleID: bundleID, preflight: preflight)
    guard let sessionID else { throw RPCError(code: -32077, message: "WDA session is missing") }
    let locator: [String: Any]
    let selectorDescription: String
    if let identifier, !identifier.isEmpty {
      locator = ["using": "accessibility id", "value": identifier]
      selectorDescription = "accessibility identifier \(identifier)"
    } else if let label, !label.isEmpty {
      let escaped = label.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "'", with: "\\'")
      let typeClause =
        type.map {
          " AND type == 'XCUIElementType\($0.replacingOccurrences(of: "'", with: ""))'"
        } ?? ""
      locator = ["using": "predicate string", "value": "label == '\(escaped)'\(typeClause)"]
      selectorDescription = "unique label \(label)" + (type.map { " (\($0))" } ?? "")
    } else {
      throw RPCError(code: -32602, message: "An accessibility identifier or label is required")
    }
    let found = try await request(
      method: "POST", path: "/session/\(sessionID)/element", body: locator)
    guard let value = found["value"] as? [String: Any],
      let elementID = (value["element-6066-11e4-a52e-4f735466cecf"] ?? value["ELEMENT"])
        as? String
    else {
      throw RPCError(
        code: -32078, message: "No element matches \(selectorDescription)")
    }
    switch action {
    case "tap":
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/element/\(elementID)/click", body: [:])
    case "type":
      guard let text else { throw RPCError(code: -32602, message: "text is required for type") }
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/element/\(elementID)/value",
        body: ["text": text, "value": text.map { String($0) }])
    case "clear":
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/element/\(elementID)/clear", body: [:])
    default:
      throw RPCError(code: -32602, message: "Supported semantic actions are tap, type, and clear")
    }
  }

  public func performXPath(
    udid: String, runtime: String, bundleID: String, xpath: String, action: String,
    text: String?, preflight: ToolchainPreflight
  ) async throws {
    try await ensureSession(
      udid: udid, runtime: runtime, bundleID: bundleID, preflight: preflight)
    guard let sessionID else { throw RPCError(code: -32077, message: "WDA session is missing") }
    let found = try await request(
      method: "POST", path: "/session/\(sessionID)/element",
      body: ["using": "xpath", "value": xpath])
    guard let value = found["value"] as? [String: Any],
      let elementID = (value["element-6066-11e4-a52e-4f735466cecf"] ?? value["ELEMENT"])
        as? String
    else { throw RPCError(code: -32078, message: "The screen-bound element is no longer present") }
    switch action {
    case "tap":
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/element/\(elementID)/click", body: [:])
    case "type":
      guard let text else { throw RPCError(code: -32602, message: "text is required for type") }
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/element/\(elementID)/value",
        body: ["text": text, "value": text.map { String($0) }])
    case "clear":
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/element/\(elementID)/clear", body: [:])
    default:
      throw RPCError(code: -32602, message: "The screen-bound element does not support \(action)")
    }
  }

  public func performFrameAction(
    udid: String, runtime: String, bundleID: String, frame: ElementFrame, action: String,
    arguments: [String: JSONValue] = [:], preflight: ToolchainPreflight
  ) async throws {
    try await ensureSession(
      udid: udid, runtime: runtime, bundleID: bundleID, preflight: preflight)
    guard let sessionID else { throw RPCError(code: -32077, message: "WDA session is missing") }
    let centerX = frame.x + frame.width / 2
    let centerY = frame.y + frame.height / 2
    switch action {
    case "tap":
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/wda/tap",
        body: ["x": centerX, "y": centerY])
    case "scrollUp", "scrollDown":
      let upperY = frame.y + frame.height * 0.3
      let lowerY = frame.y + frame.height * 0.7
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/wda/dragfromtoforduration",
        body: [
          "fromX": centerX, "fromY": action == "scrollUp" ? lowerY : upperY,
          "toX": centerX, "toY": action == "scrollUp" ? upperY : lowerY,
          "duration": 0.35,
        ])
    case "doubleTap":
      for _ in 0..<2 {
        _ = try await request(
          method: "POST", path: "/session/\(sessionID)/wda/tap",
          body: ["x": centerX, "y": centerY])
        try await Task.sleep(for: .milliseconds(80))
      }
    case "longPress":
      let duration = min(max(arguments["duration"]?.numberValue ?? 0.8, 0.2), 5)
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/wda/dragfromtoforduration",
        body: [
          "fromX": centerX, "fromY": centerY, "toX": centerX, "toY": centerY,
          "duration": duration,
        ])
    case "swipe":
      let direction = arguments["direction"]?.stringValue ?? "up"
      let points = frameSwipePoints(frame: frame, direction: direction)
      let duration = boundedDuration(arguments["durationMS"]?.numberValue)
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/wda/dragfromtoforduration",
        body: [
          "fromX": points.fromX, "fromY": points.fromY,
          "toX": points.toX, "toY": points.toY, "duration": duration,
        ])
    case "drag":
      guard let fromX = arguments["fromX"]?.numberValue,
        let fromY = arguments["fromY"]?.numberValue,
        let toX = arguments["toX"]?.numberValue,
        let toY = arguments["toY"]?.numberValue
      else {
        throw RPCError(
          code: -32602, message: "drag requires fromX, fromY, toX, and toY fractions")
      }
      let start = point(in: frame, x: fromX, y: fromY)
      let end = point(in: frame, x: toX, y: toY)
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/wda/dragfromtoforduration",
        body: [
          "fromX": start.x, "fromY": start.y, "toX": end.x, "toY": end.y,
          "duration": boundedDuration(arguments["durationMS"]?.numberValue),
        ])
    case "setSlider":
      guard let value = arguments["value"]?.numberValue else {
        throw RPCError(code: -32602, message: "setSlider requires a value from 0 through 1")
      }
      let target = point(in: frame, x: value, y: 0.5)
      _ = try await request(
        method: "POST", path: "/session/\(sessionID)/wda/tap",
        body: ["x": target.x, "y": target.y])
    default:
      throw RPCError(code: -32602, message: "The resolved frame does not support \(action)")
    }
  }

  private func point(in frame: ElementFrame, x: Double, y: Double) -> (x: Double, y: Double) {
    let normalizedX = min(max(x, 0), 1)
    let normalizedY = min(max(y, 0), 1)
    return (
      frame.x + frame.width * normalizedX,
      frame.y + frame.height * normalizedY
    )
  }

  private func boundedDuration(_ milliseconds: Double?) -> Double {
    min(max(milliseconds ?? 350, 80), 2_000) / 1_000
  }

  private func frameSwipePoints(
    frame: ElementFrame, direction: String
  ) -> (fromX: Double, fromY: Double, toX: Double, toY: Double) {
    let fractions: (Double, Double, Double, Double)
    switch direction.lowercased() {
    case "down": fractions = (0.5, 0.25, 0.5, 0.75)
    case "left": fractions = (0.75, 0.5, 0.25, 0.5)
    case "right": fractions = (0.25, 0.5, 0.75, 0.5)
    default: fractions = (0.5, 0.75, 0.5, 0.25)
    }
    let start = point(in: frame, x: fractions.0, y: fractions.1)
    let end = point(in: frame, x: fractions.2, y: fractions.3)
    return (start.x, start.y, end.x, end.y)
  }

  public func performCoordinateTap(
    udid: String, runtime: String, bundleID: String, normalizedX: Double,
    normalizedY: Double, preflight: ToolchainPreflight
  ) async throws {
    try await ensureSession(
      udid: udid, runtime: runtime, bundleID: bundleID, preflight: preflight)
    guard let sessionID else { throw RPCError(code: -32077, message: "WDA session is missing") }
    let windowSize = try await resolveWindowSize(for: sessionID)
    let point = WDANormalizedPoint(x: normalizedX, y: normalizedY).scaled(
      width: windowSize.width, height: windowSize.height)
    _ = try await request(
      method: "POST", path: "/session/\(sessionID)/wda/tap",
      body: ["x": point.x, "y": point.y])
  }

  public func performCoordinateSwipe(
    udid: String, runtime: String, bundleID: String,
    startX: Double, startY: Double, endX: Double, endY: Double,
    durationMS: Int = 350, preflight: ToolchainPreflight
  ) async throws {
    try await ensureSession(
      udid: udid, runtime: runtime, bundleID: bundleID, preflight: preflight)
    guard let sessionID else { throw RPCError(code: -32077, message: "WDA session is missing") }
    let windowSize = try await resolveWindowSize(for: sessionID)
    let start = WDANormalizedPoint(x: startX, y: startY).scaled(
      width: windowSize.width, height: windowSize.height)
    let end = WDANormalizedPoint(x: endX, y: endY).scaled(
      width: windowSize.width, height: windowSize.height)
    let duration = Double(max(80, min(durationMS, 2_000))) / 1_000
    _ = try await request(
      method: "POST", path: "/session/\(sessionID)/wda/dragfromtoforduration",
      body: [
        "fromX": start.x, "fromY": start.y,
        "toX": end.x, "toY": end.y,
        "duration": duration,
      ])
  }

  private func resolveWindowSize(for sessionID: String) async throws -> (
    width: Double, height: Double
  ) {
    if let cachedWindowSize { return cachedWindowSize }
    let response = try await request(path: "/session/\(sessionID)/window/rect")
    guard let value = response["value"] as? [String: Any],
      let width = numeric(value["width"]), let height = numeric(value["height"]),
      width > 0, height > 0
    else {
      throw RPCError(code: -32077, message: "WDA returned an invalid Simulator window size")
    }
    let size = (width: width, height: height)
    cachedWindowSize = size
    return size
  }

  private func ensureSession(
    udid: String, runtime: String, bundleID: String, preflight: ToolchainPreflight
  ) async throws {
    try await ensureRunning(udid: udid, runtime: runtime, preflight: preflight)
    if sessionID != nil, sessionBundleID == bundleID { return }
    if let sessionID {
      _ = try? await request(method: "DELETE", path: "/session/\(sessionID)")
      self.sessionID = nil
      sessionBundleID = nil
      cachedWindowSize = nil
    }
    let response = try await request(
      method: "POST", path: "/session",
      body: [
        "capabilities": [
          "alwaysMatch": [
            "bundleId": bundleID,
            // The host already launched the app. Avoid a second XCTest-driven relaunch and
            // quiescence wait, which can kill sessions for continuously animated RN/Expo apps.
            "forceAppLaunch": false,
            "shouldWaitForQuiescence": false,
            "waitForIdleTimeout": 0,
            "useSingletonTestManager": false,
          ]
        ]
      ])
    sessionID =
      (response["sessionId"] as? String)
      ?? ((response["value"] as? [String: Any])?["sessionId"] as? String)
    guard sessionID != nil else {
      throw RPCError(code: -32077, message: "WDA could not create an application session")
    }
    sessionBundleID = bundleID
    cachedWindowSize = nil
  }

  private func ensureRunning(
    udid: String, runtime: String, preflight: ToolchainPreflight
  ) async throws {
    if process?.isRunning == true, activeUDID == udid,
      (try? await request(path: "/status")) != nil
    {
      return
    }
    await stop()
    let status = WDACompatibilityGate.status(
      preflight: preflight, runtime: runtime, stateRoot: stateRoot)
    guard status.availability == .ready, let cache = status.cacheDirectory,
      let receipt = try? WDACompatibilityGate.loadReceipt(from: cache),
      let xcodebuild = preflight.xcodebuildPath,
      let developer = preflight.developerDirectory
    else {
      throw RPCError(code: -32072, message: status.detail)
    }
    let child = Process()
    let output = Pipe()
    child.executableURL = URL(fileURLWithPath: xcodebuild)
    child.arguments = [
      "-xctestrun", receipt.xctestrunPath, "-destination", "id=\(udid)",
      "test-without-building",
    ]
    child.standardOutput = output
    child.standardError = output
    child.environment = ProcessInfo.processInfo.environment.merging(
      ["DEVELOPER_DIR": developer]) { _, managed in managed }
    let outputHandle = output.fileHandleForReading
    outputHandle.readabilityHandler = { handle in
      if handle.availableData.isEmpty { handle.readabilityHandler = nil }
    }
    do {
      try child.run()
    } catch {
      outputHandle.readabilityHandler = nil
      throw error
    }
    processOutputHandle = outputHandle
    process = child
    activeUDID = udid
    for _ in 0..<120 {
      if !child.isRunning { break }
      if let response = try? await request(path: "/status"),
        let value = response["value"] as? [String: Any], value["ready"] as? Bool == true
      {
        return
      }
      try await Task.sleep(for: .milliseconds(250))
    }
    await stop()
    throw RPCError(code: -32077, message: "WebDriverAgent did not become ready within 30 seconds")
  }

  private func request(
    method: String = "GET", path: String, body: [String: Any]? = nil
  ) async throws -> [String: Any] {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.timeoutInterval = 20
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw RPCError(code: -32077, message: "WebDriverAgent request failed") }
    if let value = json["value"] as? [String: Any], let message = value["message"] as? String,
      value["error"] != nil
    {
      throw RPCError(code: -32078, message: message)
    }
    return json
  }

  private func numeric(_ value: Any?) -> Double? {
    switch value {
    case let value as Double: value
    case let value as Int: Double(value)
    case let value as NSNumber: value.doubleValue
    default: nil
    }
  }
}

final class WDAHierarchyParser: NSObject, XMLParserDelegate {
  private var elements: [UIElement] = []
  private var indices: [Int] = []
  private var childCounts: [Int] = [0]
  private var typeCounts: [[String: Int]] = [[:]]
  private var typePath: [String] = []
  private var owningApplication = "unknown"

  static func parse(_ xml: String) throws -> [UIElement] {
    let delegate = WDAHierarchyParser()
    let parser = XMLParser(data: Data(xml.utf8))
    parser.delegate = delegate
    guard parser.parse() else {
      throw RPCError(
        code: -32079, message: parser.parserError?.localizedDescription ?? "Invalid WDA hierarchy")
    }
    return delegate.elements
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes: [String: String] = [:]
  ) {
    let sibling = childCounts[childCounts.count - 1]
    childCounts[childCounts.count - 1] += 1
    indices.append(sibling)
    childCounts.append(0)
    if let bundle = attributes["bundleId"] { owningApplication = bundle }
    let type = attributes["type"] ?? elementName
    let typeIndex = (typeCounts[typeCounts.count - 1][type] ?? 0) + 1
    typeCounts[typeCounts.count - 1][type] = typeIndex
    typePath.append("\(type)[\(typeIndex)]")
    typeCounts.append([:])
    let visible = attributes["visible"] != "false"
    let enabled = attributes["enabled"] != "false"
    let accessible = attributes["accessible"] == "true"
    let actions: [String]
    if type.contains("TextField") || type.contains("SearchField")
      || type.contains("SecureTextField") || type.contains("TextView")
    {
      actions = ["tap", "type", "clear"]
    } else if type.contains("ScrollView") || type.contains("CollectionView")
      || type.contains("Table") || type.contains("WebView")
    {
      actions = ["scrollUp", "scrollDown"]
    } else if type.contains("Button") || type.contains("Cell") || type.contains("Link")
      || type.contains("Switch") || type.contains("Toggle") || type.contains("Tab")
    {
      actions = ["tap"]
    } else {
      actions = []
    }
    let actionable: Bool
    if let reportedHittable = attributes["hittable"] {
      actionable = reportedHittable == "true"
    } else {
      // WDA omits `hittable` from page source by default because it is expensive. Native control
      // roles remain executable; non-native framework nodes must opt in through accessibility.
      actionable = !actions.isEmpty || accessible
    }
    elements.append(
      UIElement(
        type: type.replacingOccurrences(of: "XCUIElementType", with: ""),
        identifier: nonempty(attributes["name"]), label: nonempty(attributes["label"]),
        value: nonempty(attributes["value"]), enabled: enabled,
        selected: attributes["selected"] == "true",
        focused: attributes["focused"].map { $0 == "true" },
        visible: visible,
        hittable: visible && enabled && actionable,
        frame: .init(
          x: Double(attributes["x"] ?? "") ?? 0, y: Double(attributes["y"] ?? "") ?? 0,
          width: Double(attributes["width"] ?? "") ?? 0,
          height: Double(attributes["height"] ?? "") ?? 0),
        childPath: indices.map(String.init).joined(separator: "."),
        xpath: "/" + typePath.joined(separator: "/"),
        owningApplication: owningApplication, availableActions: actions,
        accessible: accessible))
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    _ = indices.popLast()
    _ = childCounts.popLast()
    _ = typeCounts.popLast()
    _ = typePath.popLast()
  }

  private func nonempty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}
