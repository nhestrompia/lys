# Lys

Lys is a macOS app for building and testing iOS apps with agent-assisted, semantic verification.

The project is in public alpha.

## Install Lys

Download the latest signed and notarized Apple-silicon DMG from
[GitHub Releases](https://github.com/nhestrompia/lys/releases/latest), open it, and drag `Lys.app`
to **Applications**. The release includes a SHA-256 checksum alongside the DMG.

## Requirements

- Apple Silicon Mac
- macOS 26.2 or newer
- Swift 6.2 or newer
- Full Xcode with an iOS Simulator runtime
- [AXe 1.8.0](https://github.com/cameroncooke/axe) for the in-app Simulator surface
- Node.js/npm when using a managed ACP bridge or Expo project

## Develop Lys

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


## SDKs

- [Swift SDK](https://github.com/nhestrompia/lys-swift) — install from Swift Package Manager
- [Expo and React Native SDK](https://www.npmjs.com/package/@nhestrompia/lys) — install with `npm install @nhestrompia/lys`
- [SDK integration guide](LYS_SDK.md)

More project details are available in [ARCHITECTURE.md](ARCHITECTURE.md), [SECURITY.md](SECURITY.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT. See [LICENSE](LICENSE). Third-party components retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
