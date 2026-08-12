# Lys for Swift

Small semantic test contracts for SwiftUI and UIKit apps tested with Lys. The package adds stable
native accessibility identifiers, bounded flow declarations, authenticated test-session access,
and validated `.lys/contract.json` export. It does not embed an automation server in the app.

See the repository's `LYS_SDK.md` for examples.

## Install from a release tag

Stable releases mirror this standalone package to `lys-swift`, where SwiftPM can resolve a normal
semver tag without inheriting the desktop app's macOS 26 deployment target:

```swift
dependencies: [
  .package(url: "https://github.com/nhestrompia/lys-swift.git", from: "0.3.0")
],
targets: [
  .target(name: "YourApp", dependencies: [
    .product(name: "Lys", package: "lys-swift")
  ])
]
```

Application code imports the module with `import Lys`.
