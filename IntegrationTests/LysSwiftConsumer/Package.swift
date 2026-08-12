// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "LysSwiftConsumer",
  platforms: [.macOS(.v13)],
  dependencies: [.package(path: "../../Packages/LysSwift")],
  targets: [
    .executableTarget(
      name: "LysSwiftConsumer",
      dependencies: [.product(name: "Lys", package: "LysSwift")])
  ])
