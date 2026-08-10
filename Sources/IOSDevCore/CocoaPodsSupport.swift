import Foundation

public struct CocoaPodsRequirement: Equatable, Sendable {
  public var projectDirectory: URL
  public var reason: String
  public var installArguments: [String]

  public init(projectDirectory: URL, reason: String, installArguments: [String]) {
    self.projectDirectory = projectDirectory
    self.reason = reason
    self.installArguments = installArguments
  }
}

public enum CocoaPodsSupport {
  public static func missingInstallation(for container: URL) -> CocoaPodsRequirement? {
    missingInstallation(in: container.deletingLastPathComponent())
  }

  public static func missingInstallation(in projectDirectory: URL) -> CocoaPodsRequirement? {
    let directory = projectDirectory.standardizedFileURL
    let manager = FileManager.default
    let podfile = directory.appending(path: "Podfile")
    guard manager.fileExists(atPath: podfile.path) else { return nil }

    let lockfile = directory.appending(path: "Podfile.lock")
    let manifest = directory.appending(path: "Pods/Manifest.lock")
    let support = directory.appending(
      path: "Pods/Target Support Files", directoryHint: .isDirectory)
    let hasLockfile = manager.fileExists(atPath: lockfile.path)
    let arguments = hasLockfile ? ["install", "--deployment"] : ["install"]

    guard manager.fileExists(atPath: manifest.path) else {
      return .init(
        projectDirectory: directory,
        reason: "Pods/Manifest.lock is missing.",
        installArguments: arguments)
    }

    if hasLockfile,
      let locked = try? Data(contentsOf: lockfile),
      let installed = try? Data(contentsOf: manifest),
      locked != installed
    {
      return .init(
        projectDirectory: directory,
        reason: "The installed Pods do not match Podfile.lock.",
        installArguments: arguments)
    }

    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: support.path, isDirectory: &isDirectory), isDirectory.boolValue
    else {
      return .init(
        projectDirectory: directory,
        reason: "CocoaPods target support files are missing.",
        installArguments: arguments)
    }
    return nil
  }
}
