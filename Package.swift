// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Lys",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "IOSDevCore", targets: ["IOSDevCore"]),
    .library(name: "IOSDevUI", targets: ["IOSDevUI"]),
    .executable(name: "Lys", targets: ["IOSDevApp"]),
    .executable(name: "LysSnapshot", targets: ["IOSDevSnapshot"]),
    .executable(name: "lysd", targets: ["IOSDevRuntime"]),
    .executable(name: "lys-mcp", targets: ["IOSDevMCP"]),
  ],
  targets: [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
    .target(
      name: "IOSDevCore", dependencies: ["CSQLite"],
      resources: [.process("Resources")]),
    .target(
      name: "IOSDevUI", dependencies: ["IOSDevCore"], path: "Sources/IOSDevApp",
      exclude: ["AppMain.swift"], resources: [.process("Resources")]),
    .executableTarget(
      name: "IOSDevApp", dependencies: ["IOSDevUI"], path: "Sources/IOSDevAppMain"),
    .executableTarget(name: "IOSDevSnapshot", dependencies: ["IOSDevUI"]),
    .executableTarget(name: "IOSDevRuntime", dependencies: ["IOSDevCore"]),
    .executableTarget(name: "IOSDevMCP", dependencies: ["IOSDevCore"]),
    .testTarget(
      name: "IOSDevCoreTests", dependencies: ["IOSDevCore"],
      resources: [.copy("Fixtures")]),
  ]
)
