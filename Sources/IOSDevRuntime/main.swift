import Foundation
import IOSDevCore

@main
enum IOSDevRuntimeMain {
  static func main() async {
    let arguments = CommandLine.arguments
    guard let socketPath = value(after: "--socket", in: arguments),
      let workspacePath = value(after: "--workspace", in: arguments),
      let token = value(after: "--token", in: arguments), !token.isEmpty
    else {
      FileHandle.standardError.write(
        Data("usage: iosdevd --socket PATH --workspace PATH --token TOKEN\n".utf8))
      exit(64)
    }
    do {
      let server = try UnixSocketServer(path: socketPath)
      let service = RuntimeService(
        workspace: URL(fileURLWithPath: workspacePath), token: token,
        stateRoot: URL(fileURLWithPath: socketPath).deletingLastPathComponent())
      while true {
        let connection = try server.accept()
        Task.detached { await serve(connection, using: service) }
      }
    } catch {
      FileHandle.standardError.write(Data("iosdevd: \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }

  private static func serve(_ connection: UnixSocketConnection, using service: RuntimeService) async
  {
    var authenticated = false
    while true {
      do {
        let request = try connection.receive()
        let response = await service.handle(request, authenticated: &authenticated)
        try connection.send(response)
      } catch { return }
    }
  }

  private static func value(after option: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }
}
