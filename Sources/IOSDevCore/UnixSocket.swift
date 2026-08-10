import Darwin
import Foundation

public enum UnixSocketError: Error, LocalizedError {
  case pathTooLong
  case system(String, Int32)
  case disconnected
  public var errorDescription: String? {
    switch self {
    case .pathTooLong: "Unix socket path is too long"
    case .system(let call, let code): "\(call) failed with errno \(code)"
    case .disconnected: "Unix socket disconnected"
    }
  }
}

private func socketAddress(path: String) throws -> (sockaddr_un, socklen_t) {
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(path.utf8) + [0]
  let capacity = MemoryLayout.size(ofValue: address.sun_path)
  guard bytes.count <= capacity else { throw UnixSocketError.pathTooLong }
  withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
  let length = socklen_t(MemoryLayout<sa_family_t>.size + bytes.count)
  return (address, length)
}

public final class UnixSocketConnection: @unchecked Sendable {
  private let descriptor: Int32
  private let lock = NSLock()
  private var framer = LineFramer()
  public init(descriptor: Int32) { self.descriptor = descriptor }
  deinit { Darwin.close(descriptor) }

  public static func connect(path: String) throws -> UnixSocketConnection {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw UnixSocketError.system("socket", errno) }
    var (address, length) = try socketAddress(path: path)
    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, length)
      }
    }
    guard result == 0 else {
      let code = errno
      Darwin.close(descriptor)
      throw UnixSocketError.system("connect", code)
    }
    return .init(descriptor: descriptor)
  }

  public func send(_ envelope: RPCEnvelope) throws {
    let data = try JSONRPCCodec.encodeLine(envelope)
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        guard count > 0 else { throw UnixSocketError.system("write", errno) }
        offset += count
      }
    }
  }

  public func receive() throws -> RPCEnvelope {
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      guard count > 0 else { throw UnixSocketError.disconnected }
      let lines = lock.withLock { framer.append(Data(buffer.prefix(count))) }
      if let line = lines.first { return try JSONRPCCodec.decodeLine(line) }
    }
  }
}

public final class UnixSocketServer: @unchecked Sendable {
  private let descriptor: Int32
  public let path: String
  public init(path: String) throws {
    self.path = path
    unlink(path)
    descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw UnixSocketError.system("socket", errno) }
    var (address, length) = try socketAddress(path: path)
    let bound = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, length)
      }
    }
    guard bound == 0 else {
      let code = errno
      Darwin.close(descriptor)
      throw UnixSocketError.system("bind", code)
    }
    guard chmod(path, S_IRUSR | S_IWUSR) == 0 else {
      let code = errno
      Darwin.close(descriptor)
      unlink(path)
      throw UnixSocketError.system("chmod", code)
    }
    guard Darwin.listen(descriptor, 8) == 0 else {
      let code = errno
      Darwin.close(descriptor)
      unlink(path)
      throw UnixSocketError.system("listen", code)
    }
  }
  deinit {
    Darwin.close(descriptor)
    unlink(path)
  }
  public func accept() throws -> UnixSocketConnection {
    let client = Darwin.accept(descriptor, nil, nil)
    guard client >= 0 else { throw UnixSocketError.system("accept", errno) }
    return .init(descriptor: client)
  }
}
