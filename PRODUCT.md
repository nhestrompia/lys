# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

The shipped product is a native Apple-Silicon macOS desktop application. The schema value is marked adaptive only because the current product-record schema has no macOS value; the interface must follow macOS desktop conventions, not mobile conventions.

## Stack

Swift 6.3, SwiftUI, AppKit, Swift Package Manager, SQLite3, JSON-RPC, ACP, MCP, and Apple's installed Xcode toolchain. Distribution is a Developer-ID-signed and notarized DMG outside the Mac App Store.

## Users

The primary user is an iOS developer working in an existing Git repository who wants an AI coding agent to implement and prove application changes without manually operating Xcode. The initial audience is technically sophisticated and comfortable installing Xcode and authenticating a coding-agent CLI.

## Product Purpose

The product owns the iOS development loop from code through build, Simulator interaction, inspection, testing, and evidence-backed review. Success means a developer can complete real iOS changes while opening Xcode materially less often.

## Positioning

Unlike editor-first coding assistants, the product treats the running iOS application as first-class agent context and accepts completion only when current build, runtime, interaction, and test evidence supports it.

## Operating Context

Users open existing Xcode projects or workspaces, select an application scheme and Simulator, delegate a task to an already installed coding agent, observe work in an isolated Git worktree, and apply or discard reviewed changes. Xcode remains installed as compiler, SDK, Simulator, test, and signing infrastructure.

## Capabilities and Constraints

- Public alpha: Code, Agent, App, and Verify surfaces.
- Apple Silicon, macOS 26.2+, current stable Xcode 26.5, and installed iOS Simulator runtimes.
- Existing authenticated Codex, Claude, OpenCode, and pi agents through structured protocols, with optional managed ACP adapters and BYOK authentication.
- Git worktrees isolate agent changes; non-Git folders are browse/build-only.
- `xcodebuild`, `xcresulttool`, `simctl`, Simulator, XCTest/WebDriverAgent, and runtime logs remain Apple-toolchain-backed.
- TestFlight, real devices, LLDB UI, Instruments, Interface Builder, project generation, exhaustive crawling, and team collaboration are deferred.
- The app is not a containment boundary against a malicious local CLI.

## Brand Commitments

The working name is deliberately undecided. The product must feel lean, native, transparent, and evidence-led rather than like a smaller visual clone of Xcode or a chatbot attached to an editor.

## Evidence on Hand

The source PRD is the only supplied product artifact. No logo, production screenshots, customers, benchmarks, testimonials, or commercial claims exist and none may be fabricated.

## Product Principles

1. Organize around the app and task rather than targets and build settings.
2. Prefer deterministic semantic interaction before visual guessing.
3. Treat verification artifacts as the source of completion truth.
4. Keep advanced toolchain detail available but out of the primary path.
5. Make every mutation observable, reviewable, and recoverable.

## Accessibility & Inclusion

The macOS interface must be keyboard navigable, expose meaningful accessibility labels and status, preserve system text scaling and contrast, avoid color-only state, and respect Reduce Motion. iOS verification must surface missing accessibility identifiers as actionable automation limitations.
