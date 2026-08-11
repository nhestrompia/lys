# Lys

An AI-native macOS development and testing environment built around one trustworthy loop: run the app in Lys, execute a host-owned semantic flow, collect fresh evidence, then review the result.

This repository is an implementation-stage public-alpha foundation, not a finished release. It deliberately reports unavailable capabilities instead of silently degrading them.

## What works now

- Native SwiftUI/AppKit shell with Code, Agent, App, and Verify work areas.
- TextKit source editor with line numbers, Swift syntax coloring, find, undo, save, and read-only behavior outside a task worktree.
- Detached Git task worktrees, dirty/untracked/approved-dependency overlays, content snapshots, SHA-256 manifests, resumable crash recovery, non-overwriting three-way merge artifacts, selected apply, and discard.
- Absolute-path process execution with argument arrays, bounded incremental structured output, interrupt/terminate cancellation, and no shell-string interpolation.
- Versioned JSON-RPC over a mode-0600 Unix-domain socket with per-task authentication.
- Intent-scoped MCP bridge with strict input/output schemas, structured results, per-task runtime credentials, and dispatch-time rejection of unadvertised lifecycle or low-level UI tools. Every model receives the same small `app.describe` / `flow.*` contract.
- Native ACP v1 client with strict version negotiation, real session/prompt lifecycle, coalesced message streaming, human-readable tool progress, workspace-confined filesystem writes, contextual inline permissions, cancellation, and pinned-adapter discovery without reading credentials. Routine Lys-owned app-testing tools are approved once per task; commands and destructive actions still show their exact scope before approval.
- Xcode/project/simulator/runnable-target discovery, real build/test invocations, bounded log queries, DerivedData/result-bundle paths, and safe `simctl` command construction.
- Idempotent Simulator boot readiness and settled screenshot capture: launch previews wait for the app, then require two identical consecutive Simulator frames so SpringBoard/app-switch animations are not accepted as evidence.
- A collapsible in-app terminal records build, Metro, and Expo-preparation commands with their working directories, live/bounded output, completion state, copy, and automatic expansion on failure.
- Generation-aware evidence ledger, host-issued screen-bound action IDs, screen fingerprints, a capability-bearing observed App Graph, and BFS replay planning. Native controls use accessibility locators; React Native/Expo controls without reliable roles fall back to host-resolved XPath/frame actions without accepting model-authored coordinates.
- Host-owned app flows that reuse a compatible running app, build once only when missing or stale, keep Simulator/Metro alive, publish live progress, and finish only after every acceptance criterion passes. The lightweight Lys SDK generates `.lys/contract.json`, including fast authenticated test sessions and separate UI-authentication flows.
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
- AXe 1.8.0 for the continuous in-app Simulator surface (`brew install cameroncooke/axe/axe` for source builds)

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

For release/readiness validation across the app, runtime binaries, both SDKs, JSON Schema, npm
package contents, iOS type-check, and an external Swift consumer:

```sh
npm ci
./Scripts/test-all.sh
```

Build products are `Lys`, `lysd`, and `lys-mcp`.

## Run the app

Run directly with SwiftPM:

```sh
swift build
swift run --skip-build Lys
```

The initial `swift build` is important: it also produces the sibling `lysd` and `lys-mcp` executables used by the app.

The local launcher remains available when the selected command-line SDK needs an explicit workaround:

```sh
./Scripts/run-local.sh
```

Inside the app, open **Settings → Select Xcode…** and choose `/Applications/Xcode.app` if the toolbar reports that full Xcode is unavailable. Accept the Xcode license outside the app before expecting build or Simulator operations to work.

## Testing an Expo repository

Open the repository itself; you do not need to browse to an Xcode project. If Lys detects Expo but no native iOS container, it shows **Prepare iOS Project…**. After explicit approval, that action runs `npm ci` when dependencies are missing and then `npm exec -- expo prebuild --platform ios`. Package scripts and dependency downloads are never started without that approval.

Lys then discovers the generated workspace and scheme. Nested Expo apps in monorepositories are resolved from the selected native container, so Metro starts in the package that owns that app rather than the repository root. Choose a Simulator and select **Run**. For Expo repositories, Run starts or reuses Metro before building, then revalidates it immediately before installation and again after the app settles. Metro has a dedicated process supervisor, so cancelling a build cannot cancel the development server. If an owned server exits unexpectedly, Lys restarts it and relaunches the installed app; a failed restart is shown as a run failure rather than stale launch evidence. An existing listener is reused only when its process working directory belongs to the selected package. If port 8081 belongs to another checkout, Lys preserves that server and leases an available port from 8082–8099; the selected port is applied consistently to app defaults and launch arguments. The Run menu lets you disable development-server startup explicitly, and **Stop** also stops a Metro process started by Lys. ACP agents use the same self-healing runtime-owned server path. Isolated agent tasks copy an ignored generated `ios/` directory and reuse ignored `node_modules/` as a shared dependency cache; neither is presented as an apply-eligible source change.

If a checked-in CocoaPods workspace is missing `Pods/Manifest.lock`, its target support files, or a lock-matching installation, Lys stops before `xcodebuild` and asks permission to run the locked `pod install --deployment` in the native project directory. If CocoaPods reports lockfile drift, a separate approval is required before running unlocked `pod install`; the resulting `Podfile.lock` remains a normal reviewable repository change. CocoaPods is never executed silently.

The terminal bar above the review controls can be expanded at any time or toggled with **Command-J**. Failed commands expand it automatically. Its native TextKit transcript supports vertical and horizontal scrolling, plain-text selection/copy, Select All, Find, and stable selection while new output arrives, preserving the command, working directory, and raw output needed to diagnose a build or Metro problem.

Run now starts a continuous in-app CoreSimulator framebuffer rather than using screenshots as a display loop. AXe/FBSimulatorControl supplies raw BGRA frames directly from the selected device at 30 fps; one AppKit layer presents them without invalidating the SwiftUI workbench. A persistent HID broker delivers each click as one atomic tap transaction, while drag/trackpad events are coalesced so old pointer positions can never build up behind the current gesture. Keyboard input is translated directly to AXe HID commands instead of depending on a separately opened Simulator.app process. Video and input readiness are tracked independently: the surface accepts clicks, drags, and wheel gestures through WDA whenever the broker is missing, still connecting, or disconnects, instead of dropping input while reporting a live video stream. Lys owns the display in-app: it exposes no external-window control and hides Simulator.app if XCTest activates it while preparing semantic automation.

Stable screenshots are deliberately separate: **Capture Screenshot** records a `simctl` artifact in the evidence ledger, while WebDriverAgent continues to provide structured hierarchy, deterministic selectors, assertions, and agent actions. Those WDA actions appear immediately in the same continuous in-app stream, so the user can watch an agent test the app without treating manual gestures as verification evidence. The footer reports live frame rate; if the pinned helper is unavailable, the last screenshot and WDA interaction path remain as an explicit degraded fallback.

The Agent composer remains writable so a request can be drafted at any time. Inspection and app-testing requests run read-only in the current checkout and do not require Git; explicit edits create an isolated Git worktree. The host classifies the intent, configures the runtime, and gives every ACP-compatible model the same bounded tool contract. App journeys attach before acting, expose semantic state, record the App Graph automatically, and stream progress while the live app remains visible. Finite-flow completion is derived only from visible progress content, never tab-position announcements; terminal verification ends recovery immediately. **Stop agent** cancels the ACP turn and journey while preserving the app and development server, and every completed or stopped task receives a host-generated Done / Worked / Lacking summary. Terminal-launched development builds promote themselves to a regular macOS application so the composer can become the key text input and Lys appears in the Dock.

For headless visual QA, render the native workbench at its reference viewport:

```sh
./Scripts/snapshot-ui.sh /tmp/lys-workbench.png
```

## Configuration

Repositories may add `.lys/config.json`; all fields are optional. Only schema version 1 is accepted. Setup commands are modeled but never enabled implicitly, and secrets are Keychain references rather than values.

Repositories add the small Swift or Expo Lys SDK to generate `.lys/contract.json`. Contract flows
run deterministically across agent models; apps without a contract remain manually usable and can
be explored, but cannot receive trusted green verification. See [LYS_SDK.md](LYS_SDK.md), the
[example contract](Examples/lys-contract.json), and the checked-in
[JSON Schema](Schemas/lys-test-contract.schema.json).

The repository also ships the agent-facing [Lys integration skill](Skills/lys-integrate/SKILL.md),
which guides Swift/Expo instrumentation, authenticated setup, UI-auth flows, accessibility-safe
screen anchors, contract export, and verification.

See [ARCHITECTURE.md](ARCHITECTURE.md), [THREAT_MODEL.md](THREAT_MODEL.md), and [SECURITY.md](SECURITY.md) before extending process, archive, credential, or apply behavior.

## License

Apache License 2.0. See [LICENSE](LICENSE). WebDriverAgent source is downloaded only for a promoted tuple, checksum-verified, and remains governed by its BSD license.
