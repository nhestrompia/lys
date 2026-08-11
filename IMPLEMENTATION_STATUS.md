# Public Alpha Implementation Status

Updated 2026-08-11. Status meanings: **Implemented** is exercised locally; **Partial** has production code but lacks part of the contract; **Gated** is deliberately unavailable until its compatibility/security prerequisite passes; **Deferred** belongs to the PRD's later scope.

## Feasibility gates

| Area | Status | Remaining work |
| --- | --- | --- |
| WebDriverAgent on Xcode 26.6 / iOS 26.5 | **Implemented** | WDA 16.1.3 is pinned by commit and source checksum. Build-for-testing, loopback binding, status, structured hierarchy, accessibility-ID tap/type, and screenshot passed locally on iPhone 17e and iPhone 17 Pro. Xcode 26.5 and other runtimes remain independently gated. |
| ACP fake-agent interoperability | **Partial** | Native framing, bidirectional requests, updates, filesystem policy, permissions, cancellation, process-exit handling, and the official MCP stdio environment shape exist. Add a deterministic fake executable covering authentication and session loading. |
| Live Codex, Claude, OpenCode, and pi adapters | **Partial** | Codex ACP 1.1.14 initialize and session creation with `iosdev-mcp` passed using existing ChatGPT authentication. Claude/OpenCode config directories exist locally but their CLIs are absent; pi is absent. |
| Worktree dirty overlay/apply/recovery/conflicts | **Implemented** | Dirty, untracked, and approved ignored dependency overlays; content snapshots; submodule rejection; resumable startup recovery; selected apply; and non-overwriting three-way merge artifacts are implemented and tested. Add broader fixture coverage before release. |

## Native application

| Capability | Status | Remaining work |
| --- | --- | --- |
| Four-area shell and native editor | **Implemented** | The supplied Operate reference now drives a light native rail, Agent/App/Verify workspace, Code/Files/Git/Settings views, fixed review bar, and collapsible failure-aware terminal transcript. |
| Repository/project/scheme/simulator toolbar | **Implemented** | Repository, workspace/project, scheme, destination, Xcode selection, build, run, stop, and Simulator activation are connected to live discovery. Persist the selections across launches. |
| Durable task timeline | **Partial** | ACP message chunks are coalesced into readable turns, tool calls update in place with human labels, structured plans replace host placeholders, and permission decisions remain visible in context. Persist the timeline across launches. |
| In-app Simulator, screenshot, hierarchy, actions | **Partial** | The in-app device is a continuous 30 fps raw CoreSimulator BGRA stream with a single-layer AppKit renderer. Direct broker taps measured 11–14 ms locally; drag and scroll input drops obsolete intermediate positions. Stable `simctl` screenshots remain evidence, and WDA remains the semantic agent/verification layer whose actions are visible in the stream. Pin and manage the optional AXe helper under Application Support before release; add richer tree relationships and action configuration. |
| Verify by acceptance criterion | **Partial** | Generation-aware evidence contract exists. Add persisted criterion grouping and manifest submission validation in the UI. |
| SQLite metadata and artifact files | **Partial** | Actor-isolated schema/store is tested. Connect repositories, tasks, events, App Graph, and evidence to application/runtime lifecycle. |
| Diagnostics export | **Partial** | Secret/path redaction is tested. Add explicit export packaging, artifact selection, size bounds, and user preview. |
| Telemetry | **Implemented** | No third-party telemetry or analytics dependency is present. |

## Runtime and process isolation

| Capability | Status | Remaining work |
| --- | --- | --- |
| `iosdevd` Unix socket and per-task token | **Implemented** | Mode-0600 socket authentication is end-to-end tested manually. |
| `iosdev-mcp` typed bridge | **Implemented** | All alpha schemas are exposed and injected into live ACP sessions using the authenticated per-task Unix-socket runtime. Unsupported App Graph routes fail explicitly. |
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
| Simulator lifecycle/configuration | **Partial** | Listing, idempotent boot readiness, shutdown, appearance, install/launch, terminate, reset approval, a continuous in-app framebuffer, settled evidence screenshots, and optional adjacent Simulator activation exist. Add orientation/status-bar RPC wiring and persisted destination profiles. |
| Runtime logs | **Partial** | Bounded, process-filtered `simctl log show` queries are persisted as task evidence. Add long-lived supervised streaming and crash classification. |
| Expo development server | **Implemented** | Run starts/reuses Metro from the selected monorepo package, isolates it from build cancellation, revalidates it after build and launch, and automatically restarts/relaunches after an unexpected exit. Live forced-exit recovery passed locally. Foreign port ownership and dead launch endpoints fail explicitly. |
| Optional `.iosdev/config.json` | **Partial** | Strict versioned decoding exists. Integrate selection, nonsecret launch values, Keychain references, disabled setup approvals, device profiles, reset policy, and timeout. |

## Automation and verification

| Capability | Status | Remaining work |
| --- | --- | --- |
| WDA compatibility/checksum model | **Implemented** | The exact Xcode 26.6/iOS 26.5/WDA 16.1.3 entry is promoted; all other tuples fail closed. |
| Hierarchy normalization/selectors/fingerprints | **Implemented** | Structured XML hierarchy decoding, useful-node filtering, identifier and unique label/type actions, fingerprints, ambiguity checks, and post-action stability waits are wired. Add ancestor-qualified and stable-path actions. |
| Observed App Graph and deterministic BFS | **Implemented** | Persist it, bind live actions, separate system states in the inspector, and display stale/confidence state. |
| Evidence generations/completion contract | **Implemented** | Integrate mutations from agent filesystem notifications and configuration changes; validate submitted evidence IDs. |

## Agent integration

| Capability | Status | Remaining work |
| --- | --- | --- |
| Native ACP v1 JSON-RPC types/client | **Partial** | Version negotiation, session/prompt, coalesced streamed updates, filesystem requests, contextual inline permission UI, task-scoped choices, safe routine-runtime approvals, cancellation, and process-exit handling are wired. Add terminal methods, session recovery, authentication presentation, and a deterministic fake-agent suite. |
| Adapter manager | **Partial** | Conventional path/config detection distinguishes ready, CLI-only, config-only, and missing states. Codex ACP 1.1.14 is installed in the managed root. Add signed lock verification, install UI, Node prerequisite reporting, and redacted raw logs. |
| MCP/context injection | **Implemented** | The bridge receives the task socket/token through child environment and sessions receive the worktree, selected scheme/device, tool inventory, and completion contract. |
| BYOK/Keychain | **Missing** | Add ACP-advertised auth presentation and Keychain storage/injection without credential-file access. |

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
