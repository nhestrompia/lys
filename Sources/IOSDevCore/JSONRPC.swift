import Foundation

public enum RPCID: Codable, Hashable, Sendable {
  case int(Int)
  case string(String)
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Int.self) {
      self = .int(number)
    } else {
      self = .string(try container.decode(String.self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .int(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    }
  }
}

public struct RPCError: Codable, Error, LocalizedError, Sendable {
  public var code: Int
  public var message: String
  public var data: JSONValue?
  public init(code: Int, message: String, data: JSONValue? = nil) {
    self.code = code
    self.message = message
    self.data = data
  }

  public var errorDescription: String? {
    guard let detail = data.flatMap(Self.errorDetail)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !detail.isEmpty, detail != message
    else { return message }
    let limit = 3_000
    let concise = detail.count > limit ? "…\n" + String(detail.suffix(limit)) : detail
    return "\(message)\n\n\(concise)"
  }

  private static func errorDetail(_ value: JSONValue) -> String? {
    switch value {
    case .string(let detail):
      return detail
    case .object(let object):
      for key in ["message", "details", "detail", "error", "reason"] {
        if let value = object[key], let detail = errorDetail(value), !detail.isEmpty {
          return detail
        }
      }
      return encodedDetail(value)
    case .array:
      return encodedDetail(value)
    case .number(let number):
      return String(number)
    case .bool(let value):
      return String(value)
    case .null:
      return nil
    }
  }

  private static func encodedDetail(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value),
      let object = try? JSONSerialization.jsonObject(with: data),
      let formatted = try? JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    else { return nil }
    return String(data: formatted, encoding: .utf8)
  }
}

public struct RPCEnvelope: Codable, Sendable {
  public var jsonrpc = "2.0"
  public var id: RPCID?
  public var method: String?
  public var params: JSONValue?
  public var result: JSONValue?
  public var error: RPCError?
  public init(
    id: RPCID? = nil, method: String? = nil, params: JSONValue? = nil, result: JSONValue? = nil,
    error: RPCError? = nil
  ) {
    self.id = id
    self.method = method
    self.params = params
    self.result = result
    self.error = error
  }
}

public enum JSONRPCCodec {
  private static let encoder = JSONEncoder()
  private static let decoder = JSONDecoder()
  public static func encodeLine(_ message: RPCEnvelope) throws -> Data {
    var data = try encoder.encode(message)
    data.append(0x0A)
    return data
  }
  public static func decodeLine(_ data: Data) throws -> RPCEnvelope {
    try decoder.decode(RPCEnvelope.self, from: data.last == 0x0A ? data.dropLast() : data)
  }
}

public struct LineFramer: Sendable {
  private var buffer = Data()
  public init() {}
  public mutating func append(_ data: Data) -> [Data] {
    buffer.append(data)
    var lines: [Data] = []
    while let newline = buffer.firstIndex(of: 0x0A) {
      lines.append(buffer.prefix(upTo: newline))
      buffer.removeSubrange(...newline)
    }
    return lines
  }
}
