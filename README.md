# iOS Development Workbench

An AI-native macOS development environment built around one trustworthy loop: isolate an agent task, build and inspect the app, collect fresh evidence, then apply or discard the reviewed change set.

This repository is an implementation-stage public-alpha foundation, not a finished release. It deliberately reports unavailable capabilities instead of silently degrading them.

## What works now

- Native SwiftUI/AppKit shell with Code, Agent, App, and Verify work areas.
- TextKit source editor with line numbers, Swift syntax coloring, find, undo, save, and read-only behavior outside a task worktree.
- Detached Git task worktrees, dirty/untracked/approved-dependency overlays, content snapshots, SHA-256 manifests, resumable crash recovery, non-overwriting three-way merge artifacts, selected apply, and discard.
- Absolute-path process execution with argument arrays, bounded incremental structured output, interrupt/terminate cancellation, and no shell-string interpolation.
- Versioned JSON-RPC over a mode-0600 Unix-domain socket with per-task authentication.
- MCP bridge with the complete alpha tool inventory, per-task runtime credentials, and typed results.
- Native ACP v1 client with strict version negotiation, real session/prompt lifecycle, streamed updates, workspace-confined filesystem writes, permission presentation, cancellation, and pinned-adapter discovery without reading credentials.
- Xcode/project/simulator/runnable-target discovery, real build/test invocations, bounded log queries, DerivedData/result-bundle paths, and safe `simctl` command construction.
- Generation-aware evidence ledger, deterministic identifier and unique-label selector rules, screen fingerprints, confidence-scored observed App Graph, and BFS replay planning.
- Actor-isolated SQLite metadata store and file-based artifact model.
- Versioned optional repository configuration, checksum validation, redaction, official ACP Registry agent marks, and deny-by-default compatibility manifests.
- A promoted WebDriverAgent 16.1.3 gate for Xcode 26.6 build 17F113 and the iOS 26.5 Simulator runtime, exercised on iPhone 17e and iPhone 17 Pro with structured hierarchy, accessibility-ID tap/type, screenshot, stability waits, and loopback-only transport.

## Feasibility gates still closed

- Xcode 26.5 does not inherit the Xcode 26.6 result; it remains unsupported until it passes its own exact compatibility gate.
- Codex ACP 1.1.14 has passed initialize and session creation locally. Claude, OpenCode, and pi still require their runnable CLIs, exact adapter installs, and maintainer credentialed smoke tests.
- Optional adapter installation UI and a release-signed adapter lock are still pending. Mutable registry “latest” entries are never executed automatically.
- Notarization, Sparkle release signing, and canonical Simulator fixtures require release infrastructure and the exact supported Xcode installation.

The application never turns those gaps into a “Verified” result.

## Requirements

- Apple Silicon Mac
- macOS 26.2 or newer for the intended alpha target
- Swift 6.2 or newer for this package checkout
- Full Xcode selected as `DEVELOPER_DIR`, with its license accepted
- Installed iOS Simulator runtime

The currently promoted semantic-automation tuple is Xcode 26.6 build 17F113, WebDriverAgent 16.1.3 at commit `1449d94fb612a4e92857e7f37092dd1276b483e4`, and iOS 26.5 Simulator. Other tuples fail closed while ordinary build/run/screenshots remain available.

## Build and test

```sh
swift build
swift test
```

If Command Line Tools are selected and their SDK does not match the compiler, use the reproducible local harness:

```sh
./Scripts/test-local.sh
```

Build products are `IOSDevApp`, `iosdevd`, and `iosdev-mcp`.

## Run the app

Run directly with SwiftPM:

```sh
swift build
swift run --skip-build IOSDevApp
```

The initial `swift build` is important: it also produces the sibling `iosdevd` and `iosdev-mcp` executables used by the app.

The local launcher remains available when the selected command-line SDK needs an explicit workaround:

```sh
./Scripts/run-local.sh
```

Inside the app, open **Settings → Select Xcode…** and choose `/Applications/Xcode.app` if the toolbar reports that full Xcode is unavailable. Accept the Xcode license outside the app before expecting build or Simulator operations to work.

## Testing an Expo repository

Open the repository itself; you do not need to browse to an Xcode project. If Operate detects Expo but no native iOS container, it shows **Prepare iOS Project…**. After explicit approval, that action runs `npm ci` when dependencies are missing and then `npm exec -- expo prebuild --platform ios`. Package scripts and dependency downloads are never started without that approval.

Operate then discovers the generated workspace and scheme. Choose a Simulator and select **Run**. For Expo repositories, Run starts or reuses Metro on port 8081 before building, booting, installing, and launching the app; the Run menu lets you disable that behavior explicitly, and **Stop** also stops a Metro process started by Operate. ACP agents use the same runtime-owned development-server tools, so “build and run” does not launch an Expo development client without its bundle server. Isolated agent tasks copy an ignored generated `ios/` directory and reuse ignored `node_modules/` as a shared dependency cache; neither is presented as an apply-eligible source change.

The Agent composer remains writable so a request can be drafted at any time. Its prerequisite message explains what is still needed before sending: an open Git repository and an ACP-ready agent selected in Settings. Terminal-launched development builds promote themselves to a regular macOS application so the composer can become the key text input and Operate appears in the Dock.

For headless visual QA, render the native workbench at its reference viewport:

```sh
./Scripts/snapshot-ui.sh /tmp/iosdev-workbench.png
```

## Configuration

Repositories may add `.iosdev/config.json`; all fields are optional. Only schema version 1 is accepted. Setup commands are modeled but never enabled implicitly, and secrets are Keychain references rather than values.

See [ARCHITECTURE.md](ARCHITECTURE.md), [THREAT_MODEL.md](THREAT_MODEL.md), and [SECURITY.md](SECURITY.md) before extending process, archive, credential, or apply behavior.

## License

Apache License 2.0. See [LICENSE](LICENSE). WebDriverAgent source is downloaded only for a promoted tuple, checksum-verified, and remains governed by its BSD license.
