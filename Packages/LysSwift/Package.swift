// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Lys",
  platforms: [.iOS(.v15), .macOS(.v13)],
  products: [.library(name: "Lys", targets: ["Lys"])],
  targets: [
    .target(name: "Lys"),
    .testTarget(name: "LysTests", dependencies: ["Lys"]),
  ]
)
