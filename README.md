# Lys

Lys is a macOS app for building and testing iOS apps with agent-assisted, semantic verification.

The project is in public alpha.

## Requirements

- Apple Silicon Mac
- macOS 26.2 or newer
- Swift 6.2 or newer
- Full Xcode with an iOS Simulator runtime
- [AXe 1.8.0](https://github.com/cameroncooke/axe) for the in-app Simulator surface

## Build and test

```sh
swift build
swift test
```

For the repository's local validation harness:

```sh
./Scripts/test-local.sh
```

## Run

```sh
swift run --skip-build Lys
```

You can also use `./Scripts/run-local.sh` when the selected Xcode toolchain needs a local workaround.

## Distribution

Create a local Apple-silicon app bundle and DMG with ad-hoc signing:

```sh
LYS_VERSION=0.4.0 npm run package:macos
```

Tagged releases publish the Expo/React Native SDK to npm, expose the Swift SDK through SwiftPM,
and attach a Developer ID-signed and notarized DMG to a GitHub Release. See
[RELEASING.md](RELEASING.md) for the one-time npm and Apple setup and the release procedure.

## SDKs

- [Swift SDK](Packages/LysSwift/README.md)
- [Expo and React Native SDK](Packages/LysExpo/README.md)
- [SDK integration guide](LYS_SDK.md)

More project details are available in [ARCHITECTURE.md](ARCHITECTURE.md), [SECURITY.md](SECURITY.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT. See [LICENSE](LICENSE). Third-party components retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
