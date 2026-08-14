import Darwin
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
        Data("usage: lysd --socket PATH --workspace PATH --token TOKEN\n".utf8))
      exit(64)
    }
    do {
      let server = try UnixSocketServer(path: socketPath)
      let service = RuntimeService(
        workspace: URL(fileURLWithPath: workspacePath), token: token,
        stateRoot: URL(fileURLWithPath: socketPath).deletingLastPathComponent())
      let parentPID = getppid()
      let parentMonitor = monitorParent(
        parentPID: parentPID, socketPath: socketPath, service: service)
      let terminationSources = installTerminationSources(
        socketPath: socketPath, service: service)
      withExtendedLifetime(parentMonitor) {
        withExtendedLifetime(terminationSources) {
          while true {
            do {
              let connection = try server.accept()
              Task.detached { await serve(connection, using: service) }
            } catch {
              FileHandle.standardError.write(
                Data("lysd: \(error.localizedDescription)\n".utf8))
              exit(1)
            }
          }
        }
      }
    } catch {
      FileHandle.standardError.write(Data("lysd: \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }

  private static func monitorParent(
    parentPID: pid_t, socketPath: String, service: RuntimeService
  ) -> Task<Void, Never> {
    Task.detached(priority: .utility) {
      while true {
        try? await Task.sleep(for: .milliseconds(250))
        guard getppid() == parentPID else {
          await service.shutdown()
          unlink(socketPath)
          exit(0)
        }
      }
    }
  }

  private static func installTerminationSources(
    socketPath: String, service: RuntimeService
  ) -> [DispatchSourceSignal] {
    [SIGINT, SIGTERM].map { signalNumber in
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(
        signal: signalNumber, queue: .global(qos: .utility))
      source.setEventHandler {
        Task {
          await service.shutdown()
          unlink(socketPath)
          exit(0)
        }
      }
      source.resume()
      return source
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
