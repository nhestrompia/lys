# Public Alpha Implementation Status

Updated 2026-08-11. Status meanings: **Implemented** is exercised locally; **Partial** has production code but lacks part of the contract; **Gated** is deliberately unavailable until its compatibility/security prerequisite passes; **Deferred** belongs to the PRD's later scope.

## Feasibility gates

| Area | Status | Remaining work |
| --- | --- | --- |
| WebDriverAgent on Xcode 26.6 / iOS 26.5 | **Implemented** | WDA 16.1.3 is pinned by commit and source checksum. Build-for-testing, loopback binding, status, structured hierarchy, accessibility-ID tap/type, and screenshot passed locally on iPhone 17e and iPhone 17 Pro. Xcode 26.5 and other runtimes remain independently gated. |
| ACP fake-agent interoperability | **Implemented** | A deterministic stdio fixture exercises initialize, session creation, prompt completion, streamed updates, and adapter shutdown without depending on a model vendor. |
| Live Codex, Claude, OpenCode, and pi adapters | **Partial** | Codex ACP 1.1.14 initialize and session creation with `iosdev-mcp` passed using existing ChatGPT authentication. Claude/OpenCode config directories exist locally but their CLIs are absent; pi is absent. |
| Worktree dirty overlay/apply/recovery/conflicts | **Implemented** | Dirty, untracked, and approved ignored dependency overlays; content snapshots; submodule rejection; resumable startup recovery; selected apply; and non-overwriting three-way merge artifacts are implemented and tested. Add broader fixture coverage before release. |

## Native application

| Capability | Status | Remaining work |
| --- | --- | --- |
| Four-area shell and native editor | **Implemented** | The supplied Operate reference now drives a light native rail, Agent/App/Verify workspace, Code/Files/Git/Settings views, fixed review bar, and collapsible failure-aware terminal transcript. |
| Repository/project/scheme/simulator toolbar | **Implemented** | Repository, workspace/project, scheme, destination, Xcode selection, build, run, stop, and Simulator activation are connected to live discovery. Persist the selections across launches. |
| Durable task timeline | **Partial** | ACP message chunks are coalesced into readable turns, tool calls update in place with human labels, structured plans replace host placeholders, and permission decisions remain visible in context. Persist the timeline across launches. |
| In-app Simulator, screenshot, hierarchy, actions | **Partial** | The in-app device is a continuous 30 fps raw CoreSimulator BGRA stream with a single-layer AppKit renderer. Direct broker taps measured 11–14 ms locally; drag and scroll input drops obsolete intermediate positions. Broker readiness is handshaked independently from video, and clicks, drags, and wheel gestures automatically use WDA when direct HID is unavailable instead of becoming silent no-ops. Stable `simctl` screenshots remain evidence, and WDA remains the semantic agent/verification layer whose actions are visible in the stream. Pin and manage the optional AXe helper under Application Support before release; add richer tree relationships and action configuration. |
| Verify by acceptance criterion | **Partial** | Generation-aware evidence contract exists. Add persisted criterion grouping and manifest submission validation in the UI. |
| SQLite metadata and artifact files | **Partial** | Actor-isolated schema/store is tested and App Graph snapshots are loaded and saved by runtime session fingerprint. Connect repositories, tasks, timeline events, and all evidence to application lifecycle. |
| Diagnostics export | **Partial** | Secret/path redaction is tested. Add explicit export packaging, artifact selection, size bounds, and user preview. |
| Telemetry | **Implemented** | No third-party telemetry or analytics dependency is present. |

## Runtime and process isolation

| Capability | Status | Remaining work |
| --- | --- | --- |
| `iosdevd` Unix socket and per-task token | **Implemented** | Mode-0600 socket authentication is end-to-end tested manually. |
| `iosdev-mcp` typed bridge | **Implemented** | Strict schemas and structured results are injected into authenticated ACP sessions. Every model receives the same `app.describe` / `flow.*` surface; unadvertised lifecycle, selector, coordinate, and low-level UI calls are rejected at dispatch. |
| Absolute executable paths and argument arrays | **Implemented** | Command construction includes metacharacter tests. |
| Structured output streaming/cancellation | **Implemented** | Stdout/stderr stream incrementally as structured events, buffers are bounded and marked when truncated, and cancellation escalates from interrupt to termination after five seconds. |
| Shared keyed caches | **Partial** | Incremental DerivedData exists per task. Move it to Application Support and key by repository, scheme, Xcode build, and simulator runtime. |
| Child supervision/restart | **Partial** | Process ownership is isolated from the UI. Add runtime/agent/WDA health tracking and restart only the failed child. |

## Project, build, and Simulator

| Capability | Status | Remaining work |
| --- | --- | --- |
| Workspace-before-project discovery | **Implemented** | Internal workspace exclusion is tested. |
| Scheme/project listing | **Implemented** | Connect the result to application pickers and persistence. |
| Build-settings runnable app discovery | **Implemented** | `-showBuildSettings -json` is normalized into runnable `AppTarget` records from wrapper, bundle, build-dir, and product settings. |
| Build and result bundle | **Partial** | Real build RPC, explicit destination/DerivedData/result bundle, raw log, evidence, and pre-build CocoaPods installation checks exist. Missing locked Pods require explicit install approval; lockfile drift requires a second approval. Add streamed diagnostic parsing and `xcresulttool` issue/test extraction. |
| Simulator lifecycle/configuration | **Partial** | Listing, idempotent boot readiness, shutdown, appearance, install/launch, terminate, reset approval, a continuous in-app framebuffer, and settled evidence screenshots exist. The in-app surface owns display/input and suppresses any Simulator.app window activated by XCTest. Add orientation/status-bar RPC wiring and persisted destination profiles. |
| Runtime logs | **Partial** | Bounded, process-filtered `simctl log show` queries are persisted as task evidence. Add long-lived supervised streaming and crash classification. |
| Expo development server | **Implemented** | Run starts/reuses Metro from the selected monorepo package, isolates it from build cancellation, revalidates it after build and launch, and automatically restarts/relaunches after an unexpected exit. A foreign listener is preserved and the task leases ports 8082–8099. |
| Optional `.iosdev/config.json` | **Partial** | Strict versioned decoding exists and blueprint secret IDs resolve through local Keychain account references. Integrate nonsecret launch values, disabled setup approvals, device profiles, reset policy, and timeout. |

## Automation and verification

| Capability | Status | Remaining work |
| --- | --- | --- |
| WDA compatibility/checksum model | **Implemented** | The exact Xcode 26.6/iOS 26.5/WDA 16.1.3 entry is promoted; all other tuples fail closed. |
| Hierarchy normalization/action capabilities/fingerprints | **Implemented** | Native controls and accessible React Native, Flutter, and hybrid containers receive host-issued opaque action IDs; decorative nodes and non-causal wrappers do not. Accessibility locators are preferred; exact screen-bound XPath/frame resolution covers duplicate labels. Tap, type, clear, and scroll capabilities, ambiguity checks, and settled post-action state fingerprints are wired. |
| Observed App Graph and deterministic BFS | **Implemented** | Every observed screen persists its executable action catalog; successful state-changing actions record build-keyed transitions. Semantic taps that produce no observable response receive one physical retry, then are retired for that exact UI state instead of becoming false graph edges. Snapshots persist in SQLite and safe navigation actions replay without model-authored selectors. Add a dedicated graph inspector for stale/confidence state. |
| Interaction blueprint and flow executor | **Implemented** | Optional schema-validated `.operate/blueprint.json` files declare routes, route transitions, capabilities, parameters, authentication contexts, bounded loops, assertions, and terminal acceptance. Host BFS plans declared routes; tap/type/clear/scroll/double-tap/long-press/swipe/drag/slider actions are resolved against current controls; destructive/external actions fail closed. Opaque canvas-only apps still need accessibility semantics or a future visual adapter. |
| Evidence generations/completion contract | **Implemented** | Integrate mutations from agent filesystem notifications and configuration changes; validate submitted evidence IDs. |

## Agent integration

| Capability | Status | Remaining work |
| --- | --- | --- |
| Native ACP v1 JSON-RPC types/client | **Partial** | Version negotiation, session/prompt, coalesced streamed updates, filesystem requests, contextual inline permission UI, task-scoped choices, safe routine-runtime approvals, cancellation, process-exit handling, and a deterministic fake-agent suite are wired. Add terminal methods, session recovery, and authentication presentation. |
| Adapter manager | **Partial** | Conventional path/config detection distinguishes ready, CLI-only, config-only, and missing states. Codex ACP 1.1.14 is installed in the managed root. Add signed lock verification, install UI, Node prerequisite reporting, and redacted raw logs. |
| MCP/context injection | **Implemented** | The bridge receives the task socket/token through child environment and sessions receive the worktree, selected scheme/device, tool inventory, and completion contract. |
| Host-owned testing lifecycle | **Implemented** | Declared flows run in one host call; zero-integration flows use exact host-issued capabilities. Both attach to the current app, preserve the runtime, enforce finite progress and terminal evidence, support scoped Stop Agent, and close with deterministic Done / Worked / Lacking summaries. |
| BYOK and flow secrets | **Partial** | Blueprint auth contexts resolve logical secret IDs from local Keychain accounts without exposing values to agents or evidence. Add ACP-advertised BYOK presentation and in-app Keychain write/manage UI. |

## Release hardening

| Capability | Status | Remaining work |
| --- | --- | --- |
| License, contributor/security/threat/architecture notices | **Implemented** | Keep dependency notices synchronized when artifacts are promoted. |
| Reproducible unsigned source build | **Implemented** | `Scripts/test-local.sh` builds and runs the local suite without fetching dependencies. |
| CI fixtures/nightly Xcode matrix | **Missing** | Add GitHub Actions fake-process tests and self-hosted exact-Xcode nightly fixtures. |
| Developer ID DMG/notarization | **Gated** | Requires release identity, entitlements, packaging pipeline, and notarization credentials. |
| Sparkle EdDSA updates | **Gated** | Add pinned Sparkle dependency and signed appcast only with release keys and verified artifacts. |
| Performance/reliability budgets | **Partial** | Binary size is below budget. The live in-app surface sustains 30 fps locally, bypasses screenshot polling, updates one CALayer, and uses 11–14 ms direct HID transactions. Pointer/scroll coalescing prevents input backlogs; terminal streaming is also coalesced. Add automated cold-launch, idle memory/CPU, semantic-action, and crash-recovery measurements. |

## Explicitly deferred

TestFlight/App Store Connect, real devices, LLDB UI, Instruments, previews, Interface Builder, Xcode project editing, project generation, SourceKit-LSP completion/refactoring, automatic test generation, exhaustive crawling, image-diff/CV scoring, and team collaboration remain out of the public alpha.
